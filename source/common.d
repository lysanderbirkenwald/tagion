module actor.common;

import std.concurrency;
import std.stdio;
import std.format : format;
import std.typecons;
import core.thread;

/// Message type template
struct Msg(string name) {}

// State messages send to the supervisor
enum Ctrl {
    STARTING, // The actors is lively
    ALIVE, /// Send to the ownerTid when the task has been started
    FAIL, /// This if a something failed other than an exception
    END, /// Send for the child to the ownerTid when the task ends
}

// Signals send from the supervisor to the direct children
enum Sig {
    STOP,
}

debug enum DebugSig {
    /* STARTING = Msg!"STARTING", */
    FAIL, // Artificially make the actor fail
}

/// Control message sent to a supervisor
/// contains the Tid of the actor which send it and the state
alias CtrlMsg = Tuple!(Tid, "tid", Ctrl, "ctrl");

/// dep
bool checkCtrl(Ctrl msg) {
    // Never use receiveOnly
    CtrlMsg r = receiveOnly!(CtrlMsg);
    debug writeln(r);
    return r[1] is msg;
}

struct ActorHandle(Actor actor)  {
    import concurrency = std.concurrency;
    Tid tid;
    string taskName;

    void send(T...)(T vals) {
        concurrency.send(tid, vals);
    }

    /// generate methods
    void opDispatch(string method, Args...)(Args args) {
        send(actor.Msg!method, args);
    }

}

ActorHandle actorHandle(A)(Actor actor, string taskName) {
    Tid tid = locate(task_name);
    return ActorHandle!A(tid, taskName);
}

ActorHandle spawnActor(A)(Actor actor, string taskName) {
    alias task = actor.task;
    spawn(&task);
}

// Delegate for dealing with exceptions sent from children
void exceptionHandler(Exception e) {
    // logger.send(fatal, e);
    writeln(e);
}

Nullable!Tid maybeOwnerTid() {
    // tid is "null"
    Nullable!Tid tid;
    try {
        // Tid is asigned
        tid = ownerTid;
    }
    catch (TidMissingException) {
    }
    return tid;
}

/// Send to the owner if there is one
void sendOwner(T...)(T vals) {
    if (!maybeOwnerTid.isNull) {
        send(maybeOwnerTid.get, vals);
    }
    // Otherwise writr a message to the logger instead,
    // Otherwise just write it to stdout;
    else {
        write("No owner, writing message to stdout instead: ");
        writeln(vals);
    }
}

/// send your state to your owner
void setState(Ctrl ctrl) {
    if (!maybeOwnerTid.isNull) {
        prioritySend(maybeOwnerTid.get, thisTid, ctrl);
    }
    else {
        write("No owner, writing message to stdout instead: ");
        writeln(ctrl);
    }
}

import std.algorithm.iteration;

Tid[] spawnChildren(F)(F[] fns) /* if ( */
/*     fn.each(isSpawnable(f)); } */
/*     ) { */ {
    Tid[] tids;
    foreach (f; fns) {
        // Starting and checking the children sequentially :(
        // Also bootstrapping
        tids ~= spawn(f);
        assert(checkCtrl(Ctrl.STARTING));
        assert(checkCtrl(Ctrl.ALIVE));
    }
    return tids;
}

static class Actor {
    static Tid[] children;
    static Tid[Tid] failChildren;
    static Tid[Tid] startChildren;
    static string task_name;
    /// Static ActorHandle[] children;
    static bool stop;

    static void signal(Sig s) {
        with (Sig) final switch (s) {
        case STOP:
            stop = true;
            break;
        }
    }

    /// Controls message sent from the children.
    static void control(CtrlMsg msg) {
        with (Ctrl) final switch(Ctrl) {
        case STARTING:
            debug writeln(msg);
            startChildren[msg.tid] = msg.tid;
            break;
        case ALIVE:
            debug writeln(msg);
            if (msg.tid in failChildren) {
                startChildren.remove(msg.tid);
            }
            else {
                throw new Exception("%s: never started".format(msg.tid));
            }

            if (msg.tid in failChildren) {
                failChildren.remove(msg.tid);
            }
            break;
        case FAIL:
            debug writeln(msg);
            /// Add the failing child to the AA of children to restart
            failChildren[msg.tid] = msg.tid;
            break;
        case END:
            debug writeln(msg);
            if (msg.tid in failChildren) {
                Thread.sleep(100.msecs);
                writeln("Respawning actor");
                // Uh respawn the actor, would be easier if we had a proper actor handle instead of a tid
            }
            break;
        }
    }

    static void ownerTerminated(OwnerTerminated _e) {
        writefln("%s, Owner stopped... nothing to life for... stoping self", thisTid);
        stop = true;
    }

    // Default
    static void unknown(Variant message) {
        // For unkown messages we assert, and send a fail message to the owner
        // so we don't accidentally fill up our messagebox with garbage
        setState(Ctrl.FAIL);
        assert(0, "No delegate to deal with message: %s".format(message));
    }

    /// General actor task
    void actorTask(T...)(T receivers) {
        stop = false;

        setState(Ctrl.STARTING); // Tell the owner that you are starting.
        scope (exit) setState(Ctrl.END); // Tell the owner that you have finished.

        setState(Ctrl.ALIVE); // Tell the owner that you running
        while (!stop) {
            try {
                receive(
                        receivers,
                        &signal,
                        &control,
                        &ownerTerminated,
                        &unknown,
                );
            }
            // If we catch an exception we send it back to owner for them to deal with it.
            // Do not send shared
            catch (shared(Exception) e) {
                // Preferable FAIL would be able to carry the exception with it
                ownerTid.prioritySend(e);
                setState(Ctrl.FAIL);
                stop = true;
            }
        }
    }

    // We need to be certain that anything the task inherits from outside scope
    // is maintained as a copy and not a reference.
    void task(A...)(A args);
    /// Structure
    /* while(!stop)
        receive(
            Msgs...
            &signal,
            &control,
            &unkown,
        ))
    */
}

