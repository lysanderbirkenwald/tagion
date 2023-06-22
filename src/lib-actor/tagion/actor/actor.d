/// Actor framework implementation
module tagion.actor.actor;

import std.stdio;
import std.format : format;
import std.typecons;
import std.exception;
import std.traits;
import std.variant : Variant;
import std.format : format;
import std.traits : isCallable;

import core.thread;

import tagion.utils.pretend_safe_concurrency;
import tagion.actor.exceptions;
import tagion.basic.tagionexceptions : TagionException;

version (Posix) {
    import core.sys.posix.pthread;

    extern (C) int pthread_setname_np(pthread_t, const char*) nothrow;
}

/**
 * Message "Atom" type
 * Examples:
 * ---
 * // As a type
 * Msg!"hi";
 * // As a value
 * Msg!"hi"();
 * ---
 */
struct Msg(string name) {
}

// State messages send to the supervisor
enum Ctrl {
    STARTING, // The actors is lively
    ALIVE, /// Send to the ownerTid when the task has been started
    END, /// Send for the child to the ownerTid when the task ends
}

// Signals send from the supervisor to the direct children
enum Sig {
    STOP,
}

/// Control message sent to a supervisor
/// contains the Tid of the actor which send it and the state
alias CtrlMsg = Tuple!(string, "task_name", Ctrl, "ctrl");

bool all(Ctrl[string] aa, Ctrl ctrl) @safe nothrow {
    foreach (val; aa.byValue) {
        if (val != ctrl) {
            return false;
        }
    }
    return true;
}

bool waitfor(Ctrl[string] childrenState, Ctrl state) @safe nothrow {
    bool success = true;
    while (!(childrenState.all(state))) {
        try {
            CtrlMsg msg = receiveOnly!CtrlMsg;
            childrenState[msg.task_name] = msg.ctrl;
        }
        catch (Exception _) {
            success = false;
        }
    }
    return success;
}

import std.traits;

/// Checks if a type has the required members to be an actor
template isActor(A) {
    template isTask(args...) if (args.length == 1 && isCallable!(args[0])) {
        alias task = args[0];
        alias params = Parameters!(task);
        enum bool isTask = is(params[0] : string)
            && ParameterIdentifierTuple!(task)[0] == "task_name"
            && hasFunctionAttributes!(task, "nothrow");
    }

    enum bool isActor = hasMember!(A, "task")
        && isTask!(A.task);
}

template isFailHandler(F) {
    enum bool isFailHandler
        = is(F : void function(TaskFailure))
        || is(F : void delegate(TaskFailure));
}

/**
 * A "reference" to an actor that may or may not be spawned, we will never know
 * Params:
 *  A = an actor type
 */
struct ActorHandle(A) {
    import concurrency = tagion.utils.pretend_safe_concurrency;

    /// the tid of the spawned task
    Tid tid;
    /// the name of the possibly running task
    string task_name;

    alias Actor = A;

    @safe void send(T...)(T args) {
        locate(task_name).send(args);
        // concurrency.send(tid, args);
    }

    // pragma(msg, format("# %s:", Actor.stringof));
    version (none) static foreach (member; __traits(allMembers, Actor)) {
        // alias getMem = __traits(getMember, Actor, member);

        // enum params = Parameters!(member);
        // pragma(msg, format("\t%s:%s", member, __traits(getMember, Actor, member)));
        static if (
            isCallable!(__traits(getMember, Actor, member))
                && Parameters!(__traits(getMember, Actor, member))
            ) {
            // pragma(msg, member);
        }
    }

    /// use
    // void opDispatch(string method, Args...)(Args args) {
    //     send(actor.Msg!method, args);
    // }

}

/**
 * Create an actorHandle
 * Params:
 *   A = The type of actor you want to create a handle for
 *   task_name = the task name to search for
 * Returns: Actorhandle with type A
 * Examples:
 * ---
 * actorHandle!MyActor("my_task_name");
 * ---
 */
ActorHandle!A handle(A)(string task_name) @safe if (isActor!A) {
    Tid tid = locate(task_name);
    return ActorHandle!A(tid, task_name);
}

ActorHandle!A spawn(A, Args...)(A actor, string task_name, Args args) @safe nothrow
if (isActor!A) {
    try {
        Tid tid;
        import concurrency = tagion.utils.pretend_safe_concurrency;

        tid = concurrency.spawn(&(actor.task), task_name, args);
        writefln("spawning %s", task_name);
        tid.setMaxMailboxSize(int.sizeof, OnCrowding.throwException);
        register(task_name, tid);
        writefln("%s registered", task_name);
        return ActorHandle!A(tid, task_name);
    }
    catch (Exception e) {
        assert(0, e.msg);
    }
}

/**
 * Params:
 *   A = The type of actor you want to create a handle for
 *   task_name = the name it should be started as
 *   args = list of arguments to pass to the task function
 * Returns: An actorHandle with type A
 * Examples:
 * ---
 * spawn!MyActor("my_task_name", 42);
 * ---
 */
ActorHandle!A spawn(A, Args...)(string task_name, Args args) @safe nothrow
if (isActor!A) {
    A actor = A();
    return spawn(actor, task_name, args);
}

/*
 *
 * Params:
 *   a = an active actorhandle
 */
A respawn(A)(A actor_handle) @safe if (isActor!(A.Actor)) {
    writefln("%s", typeid(actor_handle.Actor));
    actor_handle.send(Sig.STOP);
    unregister(actor_handle.task_name);

    return spawn!(A.Actor)(actor_handle.task_name);
}

/// Nullable and nothrow wrapper around ownerTid
Nullable!Tid tidOwner() @safe nothrow {
    // tid is "null"
    Nullable!Tid tid;
    try {
        // Tid is assigned
        tid = ownerTid;
    }
    catch (TidMissingException) {
        // Tid is "just null"
    }
    catch (Exception e) {
        // logger.fatal(e);
    }
    return tid;
}

/// Send to the owner if there is one
void sendOwner(T...)(T vals) @safe {
    if (!tidOwner.isNull) {
        send(tidOwner.get, vals);
    }
    else {
        write("No owner, writing message to stdout instead: ");
        writeln(vals);
    }
}

/** 
 * Send a TaskFailure up to the owner
 * Silently fails if there is no owner
 * Does NOT exit regular control flow
*/
void fail(string task_name, Throwable t) @trusted nothrow {
    if (tidOwner.get !is Tid.init) {
        assumeWontThrow(
                ownerTid.prioritySend(
                TaskFailure(task_name, cast(immutable) t)
        )
        );
    }
}

/// send your state to your owner
void setState(Ctrl ctrl, string task_name) @safe nothrow {
    try {
        if (!tidOwner.isNull) {
            tidOwner.get.prioritySend(CtrlMsg(task_name, ctrl));
        }
        else {
            /* write("No owner, writing message to stdout instead: "); */
            /* writeln(ctrl); */
        }
    }
    catch (PriorityMessageException e) {
        /* logger.fatal(e); */
    }
    catch (Exception e) {
        /* logger.fatal(e); */
    }
}

void end(string task_name) nothrow {
    assumeWontThrow(ThreadInfo.thisInfo.cleanup);
    assumeWontThrow(setState(Ctrl.END, task_name));
}

/* 
 * Params:
 *   task_name = the name of the task
 *   args = a list of message handlers for the task
 */
void run(Args...)(string task_name, Args args) nothrow {
    bool stop = false;
    Ctrl[string] childrenState; // An AA to keep a copy of the state of the children

    void signal(Sig signal) {
        with (Sig) final switch (signal) {
        case STOP:
            stop = true;
            break;
        }
    }

    /// Controls message sent from the children.
    void control(CtrlMsg msg) {
        childrenState[msg.task_name] = msg.ctrl;
    }

    /// Stops the actor if the supervisor stops
    void ownerTerminated(OwnerTerminated) {
        writefln("%s, Owner stopped... nothing to life for... stopping self", thisTid);
        stop = true;
    }

    /**
     * The default message handler, if it's an unknown messages it will send a FAIL to the owner.
     * Params:
     *   message = literally any message
     */
    void unknown(Variant message) {
        throw new UnknownMessage("No delegate to deal with message: %s".format(message));
    }

    try {
        setState(Ctrl.STARTING, task_name); // Tell the owner that you are starting.
        scope (exit) {
            if (childrenState.length != 0) {
                foreach (child_task_name, ctrl; childrenState) {
                    if (ctrl is Ctrl.ALIVE) {
                        locate(child_task_name).send(Sig.STOP);
                    }
                }

                while (!(childrenState.all(Ctrl.END))) {
                    receive(
                            (CtrlMsg ctrl) { childrenState[ctrl.task_name] = ctrl.ctrl; },
                            (TaskFailure tf) {
                        writefln("While stopping `%s` received taskfailure: %s", task_name, tf.throwable.msg);
                    }
                    );
                }
            }
        }

        // static if(args.length == 1) {
        //     pragma(msg, format("IS taskfailure %s %s", isFailHandler!(typeof(args[$-1])), args));
        // }
        static if (args.length == 1 && isFailHandler!(typeof(args[$ - 1]))) {
            enum failhandler = () {}; /// Use the fail handler passed through `args`
        }
        else {
            enum failhandler = (TaskFailure tf) {
                if (ownerTid != Tid.init) {
                    ownerTid.prioritySend(tf);
                }
            };
        }

        setState(Ctrl.ALIVE, task_name); // Tell the owner that you are running
        while (!stop) {
            try {
                receive(
                        args, // The message handlers you pass to your Actor template
                        failhandler,
                        &signal,
                        &control,
                        &ownerTerminated,
                        &unknown,
                );
            }
            catch (Exception t) {
                fail(task_name, t);
            }
        }
    }

    // If we catch an exception we send it back to owner for them to deal with it.
    catch (Exception t) {
        fail(task_name, t);
    }
}
