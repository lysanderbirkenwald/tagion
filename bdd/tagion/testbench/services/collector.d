module tagion.testbench.services.collector;
// Default import list for bdd
import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import tagion.testbench.tools.Environment;

import core.time;

import std.path : dirName, setExtension, buildPath;
import std.file : mkdirRecurse, exists, remove;
import std.range : iota, zip, take;
import std.algorithm.iteration : map;
import std.format : format;
import std.array;
import std.exception;

import tagion.testbench.actor.util;
import tagion.crypto.SecureNet;
import tagion.crypto.Types;
import tagion.crypto.SecureInterfaceNet;
import tagion.script.execute;
import tagion.script.TagionCurrency;
import tagion.script.common;
import tagion.actor;
import tagion.utils.pretend_safe_concurrency : receiveOnly, receive, receiveTimeout;
import tagion.logger.Logger;
import tagion.services.messages;
import tagion.services.collector;
import tagion.services.DART;
import tagion.utils.StdTime;
import tagion.basic.Types : FileExtension, Buffer;
import tagion.dart.Recorder;
import tagion.dart.DARTBasic;
import tagion.communication.HiRPC;
import tagion.services.replicator : ReplicatorOptions;
import tagion.services.options : TaskNames;

enum feature = Feature(
            "collector services",
            []);

alias FeatureContext = Tuple!(
        ItWork, "ItWork",
        FeatureGroup*, "result"
);

SecureNet[] createNets(uint count, string pass_prefix = "net") @safe {
    return iota(0, count).map!((i) {
        SecureNet net = new StdSecureNet();
        net.generateKeyPair(format("%s_%s", pass_prefix, i));
        return net;
    }).array;
}

TagionBill[] createBills(const(SecureNet)[] bill_nets, uint amount) @safe {
    return bill_nets.map!((net) =>
            TagionBill(TGN(amount), currentTime, net.pubkey, Buffer.init)
    ).array;
}

const(DARTIndex)[] insertBills(TagionBill[] bills, ref RecordFactory.Recorder rec) @safe {
    rec.insert(bills, Archive.Type.ADD);
    return rec[].map!((a) => a.dart_index).array;
}

@safe @Scenario("it work", [])
class ItWork {
    enum dart_service = "dart_service_task";
    DARTServiceHandle dart_handle;
    CollectorServiceHandle collector_handle;

    TagionBill[] input_bills;
    SecureNet[] input_nets;

    immutable SecureNet node_net;
    this() {
        SecureNet _net = new StdSecureNet();
        _net.generateKeyPair("very secret");
        node_net = (() @trusted => cast(immutable) _net)();
    }

    @Given("i have a collector service")
    Document service() @safe {
        thisActor.task_name = "collector_tester_task";
        log.registerSubscriptionTask(thisActor.task_name);
        submask.subscribe(reject_collector);

        immutable task_names = TaskNames();
        { // Start dart service
            immutable opts = DARTOptions(
                    buildPath(env.bdd_log, __MODULE__),
                    "dart".setExtension(FileExtension.dart),
            );
            immutable replicator_folder = buildPath(opts.dart_path.dirName, "replicator");
            immutable replicator_opts = ReplicatorOptions(replicator_folder);

            mkdirRecurse(replicator_folder);
            mkdirRecurse(opts.dart_filename.dirName);

            if (opts.dart_path.exists) {
                opts.dart_path.remove;
            }

            import tagion.dart.DART;

            DART.create(opts.dart_path, node_net);

            dart_handle = spawn!DARTService(task_names.dart, opts, replicator_opts, task_names, node_net);
            check(waitforChildren(Ctrl.ALIVE), "dart service did not alive");
        }

        auto record_factory = RecordFactory(node_net);
        auto insert_recorder = record_factory.recorder;

        input_nets = createNets(10, "input");
        input_bills = input_nets.createBills(100_000);
        input_bills.insertBills(insert_recorder);
        dart_handle.send(dartModify(), RecordFactory.uniqueRecorder(insert_recorder), immutable int(0));

        {
            import tagion.utils.pretend_safe_concurrency;

            register(task_names.tvm, thisTid);
        }
        immutable collector = CollectorService(node_net, task_names);
        collector_handle = spawn(collector, task_names.collector);
        check(waitforChildren(Ctrl.ALIVE), "CollectorService never alived");
        return result_ok;
    }

    @When("i send a contract")
    Document contract() {
        const script = PayScript(iota(0, 10).map!(_ => TagionBill.init).array).toDoc;
        const s_contract = sign(input_nets, input_bills.map!(a => a.toDoc).array, null, script);

        import std.stdio;
        import tagion.hibon.HiBONJSON;

        writeln(s_contract.toPretty);

        const hirpc = HiRPC(node_net);
        immutable sender = hirpc.sendDaMonies(s_contract);
        collector_handle.send(inputHiRPC(), hirpc.receive(sender.toDoc));

        auto collected = receiveOnlyTimeout!(signedContract, immutable(CollectedSignedContract)*)[1];

        check(collected !is null, "The collected was null");
        // check(collected.inputs.length == inputs.length, "The lenght of inputs were not the same");
        // check(collected.inputs.map!(a => node_net.dartIndex(a)).array == inputs, "The collected archives did not match the index");
        return result_ok;
    }

    @When("i send an contract with no inputs")
    Document noInputs() {
        const outputs = PayScript(iota(0, 10).map!(_ => TagionBill.init).array).toDoc;
        const contract = Contract(DARTIndex[].init, DARTIndex[].init, outputs);
        const s_contract = SignedContract(Signature[].init, contract);

        const hirpc = HiRPC(node_net);
        immutable sender = hirpc.sendDaMonies(s_contract);
        //immutable sender = hirpc.sendDaMonies(contract);
        collector_handle.send(inputHiRPC(), hirpc.receive(sender.toDoc));

        auto result = receiveOnlyTimeout!(Topic, string, const(Document));
        check(result[1] == "hirpc_invalid_signed_contract", "did not reject for the expected reason");

        return result_ok;
    }

    @When("i send an contract with invalid signatures inputs")
    Document invalidSignatures() {
        import std.random;

        const script = PayScript(iota(0, 10).map!(_ => TagionBill.init).array).toDoc;
        const s_contract = sign(input_nets.randomShuffle, input_bills.map!(a => a.toDoc).array, null, script);

        const hirpc = HiRPC(node_net);
        immutable sender = hirpc.sendDaMonies(s_contract);
        collector_handle.send(inputHiRPC(), hirpc.receive(sender.toDoc));

        auto result = receiveOnlyTimeout!(Topic, string, const(Document));
        check(result[1] == "contract_no_verify", "did not reject for the expected reason got, %s".format(result[1]));

        return result_ok;
    }

    @When("i send a contract with input which are not in the dart")
    Document inTheDart() {
        const script = PayScript(iota(0, 10).map!(_ => TagionBill.init).array).toDoc;

        const invalid_inputs = createNets(10, "not_int_dart")
            .createBills(100_000)
            .map!(a => a.toDoc)
            .array;

        const s_contract = sign(input_nets, invalid_inputs, null, script);

        const hirpc = HiRPC(node_net);
        immutable sender = hirpc.sendDaMonies(s_contract);
        collector_handle.send(inputHiRPC(), hirpc.receive(sender.toDoc));

        auto result = receiveOnlyTimeout!(Topic, string, const(Document));
        check(result[1] == "missing_archives", "did not reject for the expected reason");

        return result_ok;
    }

    @Then("i stop the services")
    Document collectedSignedContract() {
        dart_handle.send(Sig.STOP);
        collector_handle.send(Sig.STOP);
        waitforChildren(Ctrl.END);

        return result_ok;
    }
}
