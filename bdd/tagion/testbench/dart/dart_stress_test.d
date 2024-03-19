module tagion.testbench.dart.dart_stress_test;
// Default import list for bdd
import std.algorithm : each, equal, filter, map, sort;
import std.datetime.stopwatch;
import std.file : mkdirRecurse;
import std.format : format;
import std.path : buildPath, setExtension;
import std.random : MinstdRand0, randomSample, randomShuffle;
import std.range;
import std.stdio;
import std.typecons : Tuple;
import tagion.Keywords;
import tagion.behaviour;
import tagion.communication.HiRPC;
import tagion.communication.HiRPC;
import tagion.crypto.SecureInterfaceNet : HashNet, SecureNet;
import tagion.dart.DART : DART;
import tagion.dart.DARTBasic : DARTIndex, dartIndex;
import tagion.dart.DARTFakeNet;
import tagion.dart.DARTFile : DARTFile;
import tagion.dart.DARTcrud : dartRead;
import tagion.dart.Recorder : Archive, RecordFactory;
import tagion.hibon.Document;
import tagion.hibon.HiBONJSON : toPretty;
import tagion.hibon.HiBONJSON : toPretty;
import tagion.hibon.HiBONRecord;
import tagion.testbench.dart.dart_helper_functions;
import tagion.testbench.dart.dartinfo;
import tagion.testbench.tools.Environment;
import tagion.utils.Random;

enum feature = Feature(
            "Dart pseudo random stress test",
            ["All test in this bdd should use dart fakenet."]);

alias FeatureContext = Tuple!(
        AddPseudoRandomData, "AddPseudoRandomData",
        FeatureGroup*, "result"
);

@safe @Scenario("Add pseudo random data.",
        [])
class AddPseudoRandomData {
    DART db1;

    DartInfo info;
    const ulong samples;
    const ulong number_of_records;
    ulong[][] data;

    this(DartInfo info, const ulong samples, const ulong number_of_records) {
        check(samples % number_of_records == 0,
                format("Number of samples %s and records %s each time does not match.", samples, number_of_records));
        this.info = info;
        this.samples = samples;
        this.number_of_records = number_of_records;
    }

    @Given("I have one dartfile.")
    Document dartfile() {
        writeln(info.dartfilename);
        DARTFile.create(info.dartfilename, info.net);
        Exception dart_exception;
        db1 = new DART(info.net, info.dartfilename, dart_exception);
        check(dart_exception is null, format("Failed to open DART %s %s",info.dartfilename, dart_exception.msg));
        writeln("after opening");
        return result_ok;
    }

    @Given("I have a pseudo random sequence of data stored in a table with a seed.")
    Document seed() {
        check(!info.fixed_states.empty, "Pseudo random sequence not generated");
        return result_ok;
    }

    @When("I increasingly add more data in each recorder and time it.")
    Document it() {

        auto insert_watch = StopWatch(AutoStart.no);
        auto read_watch = StopWatch(AutoStart.no);
        auto remove_watch = StopWatch(AutoStart.no);

        RecordFactory.Recorder[] recorders;

        foreach (i; 0 .. samples / number_of_records) {
            writefln("running %s", i);

            auto docs = info.fixed_states.take(number_of_records)
                .map!(a => DARTFakeNet.fake_doc(a));

            auto recorder = db1.recorder();

            recorders ~= recorder;

            recorder.insert(docs, Archive.Type.ADD);
            auto dart_indices = recorder[]
                .map!(a => a.dart_index);

            ulong[] insert_add_single_time;
            insert_watch.start();
            db1.modify(recorder);
            insert_watch.stop();
            insert_add_single_time ~= insert_watch.peek.total!"msecs";
            read_watch.start();
            auto sender = dartRead(dart_indices, info.hirpc);
            auto receiver = info.hirpc.receive(sender.toDoc);
            auto result = db1(receiver, false);
            const doc = result.message[Keywords.result].get!Document;
            read_watch.stop();
            insert_add_single_time ~= read_watch.peek.total!"msecs";
            data ~= insert_add_single_time;

            auto recorder_read = db1.recorder(doc);
            check(equal(recorder_read[].map!(a => a.filed.data), recorder[].map!(a => a.filed.data)), "data not the same");
        }
        import tagion.dart.Recorder : Remove;

        foreach (i, recorder; recorders.enumerate) {
            writefln("remove %s", i);
            remove_watch.start();
            db1.modify(recorder.changeTypes(Remove));
            remove_watch.stop();
            data[i] ~= remove_watch.peek.total!"msecs";

        }

        const long insert_time = insert_watch.peek.total!"msecs";
        const long read_time = read_watch.peek.total!"msecs";
        const long remove_time = remove_watch.peek.total!"msecs";
        const total_time = insert_time + read_time + remove_time;

        writefln("INSERT took %d msecs", insert_time);
        writefln("READ took %d msecs", read_time);
        writefln("REMOVE took %d msecs", remove_time);

        writefln("TOTAL: %d msecs. IRR pr. sec: %.1f", insert_time + read_time + remove_time, samples / double(
                total_time) * 1000.0);

        return result_ok;
    }

    @Then("the data should be read and checked.")
    Document checked() {

        auto fout = File(format("%s", buildPath(info.module_path, "dart_stress_test.csv")), "w");

        scope (exit) {
            fout.close();
        }

        fout.writeln("INSERT,READ,REMOVE");
        foreach (single_time; data) {
            fout.writefln("%(%s, %)", single_time);
        }

        db1.close();
        return result_ok;
    }

}
