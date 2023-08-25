/// Test for [tagion.services.inputvalidator]
module tagion.testbench.services.inputvalidator;
// Default import list for bdd
import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import tagion.testbench.tools.Environment;

import nngd;
import core.time;
import std.typecons;
import std.stdio;
import tagion.actor;
import tagion.actor.exceptions;
import concurrency = tagion.utils.pretend_safe_concurrency;
import tagion.services.inputvalidator;
import tagion.services.messages;
import tagion.communication.HiRPC;
import tagion.tools.Basic;
import tagion.hibon.HiBON;
import tagion.hibon.HiBONJSON;
import tagion.hibon.HiBONBase;

enum feature = Feature(
            "Inputvalidator service",
            [
        "This feature should verify that the inputvalidator accepts valid and rejects invalid LEB128 input over a socket"
]);

alias FeatureContext = Tuple!(
        SendADocumentToTheSocket, "SendADocumentToTheSocket",
        SendRandomBuffer, "SendRandomBuffer",
        SendMalformedHiBON, "SendMalformedHiBON",
        SendPartialHiBON, "SendPartialHiBON",
        FeatureGroup*, "result"
);

@safe @Scenario("send a document to the socket", [])
class SendADocumentToTheSocket {
    NNGSocket sock;
    const string sock_path;
    this(string _sock_path) @trusted {
        sock = NNGSocket(nng_socket_type.NNG_SOCKET_PUSH);
        sock_path = _sock_path;
    }

    Document doc;

    @Given("a inputvalidator")
    Document aInputvalidator() {
        waitforChildren(Ctrl.ALIVE);
        return result_ok;
    }

    @When("we send a `Document` on a socket")
    Document aSocket() @trusted {
        sock.sendtimeout = msecs(1000);
        sock.sendbuf = 4096;
        int rc = sock.dial(sock_path);
        check(rc == 0, format("Failed to dial %s", nng_errstr(rc)));
        HiRPC hirpc;
        auto hibon = new HiBON();
        hibon["$test"] = 5;
        const sender = hirpc.act(hibon);
        doc = sender.toDoc;
        rc = sock.send(doc.serialize);
        check(rc == 0, format("Failed to send %s", nng_errstr(rc)));

        return result_ok;
    }

    @Then("we receive back the Document in our mailbox")
    Document ourMailbox() @trusted {
        auto res = concurrency.receiveOnly!(Tuple!(inputDoc, Document));
        writeln("Receive back: ", res[1].toPretty);
        check(res[1] == doc, "The value was not the same as we sent");
        return result_ok;
    }
}

@safe @Scenario("send random buffer", [])
class SendRandomBuffer {

    NNGSocket sock;
    const string sock_path;
    this(string _sock_path) @trusted {
        sock = NNGSocket(nng_socket_type.NNG_SOCKET_PUSH);
        sock_path = _sock_path;
    }

    @Given("a inputvalidator")
    Document inputvalidator() {
        waitforChildren(Ctrl.ALIVE);
        return result_ok;
    }

    @When("we send a `random_buffer` on a socket")
    Document socket() @trusted {
        sock.sendtimeout = msecs(1000);
        sock.sendbuf = 4096;
        int rc = sock.dial(sock_path);
        check(rc == 0, format("Failed to dial %s", nng_errstr(rc)));

        // import tagion.utils.Random;
        // import std.array;
        // import std.range : take;
        // ubyte[] rnd_buffer = Random!uint().take(32).array;
        ubyte[] rnd_buffer = new ubyte[](32);
        writefln("rnd_buffer: %s", rnd_buffer);

        rc = sock.send(rnd_buffer);
        check(rc == 0, format("Failed to send %s", nng_errstr(rc)));
        return result_ok;
    }

    @Then("the inputvalidator rejects")
    Document rejects() {
        import tagion.testbench.actor.util;

        check(concurrency.receiveTimeout(Duration.zero, (inputDoc _, Document __) {}) == false, "should not have received anything");
        return Document();
    }

}

@safe @Scenario("send malformed HiBON", [])
class SendMalformedHiBON {

    NNGSocket sock;
    const string sock_path;
    this(string _sock_path) @trusted {
        sock = NNGSocket(nng_socket_type.NNG_SOCKET_PUSH);
        sock_path = _sock_path;
    }

    @Given("a inputvalidator")
    Document inputvalidator() {
        waitforChildren(Ctrl.ALIVE);
        return Document();
    }

    @When("we send a `malformed_hibon` on a socket")
    Document socket() {
        return Document();
    }

    @Then("the inputvalidator rejects")
    Document rejects() {
        return Document();
    }

}

@safe @Scenario("send partial HiBON", [])
class SendPartialHiBON {

    NNGSocket sock;
    const string sock_path;
    this(string _sock_path) @trusted {
        sock = NNGSocket(nng_socket_type.NNG_SOCKET_PUSH);
        sock_path = _sock_path;
    }

    @Given("a inputvalidator")
    Document inputvalidator() {
        waitforChildren(Ctrl.ALIVE);
        return Document();
    }

    @When("we send a `partial_hibon` on a socket")
    Document socket() {
        return Document();
    }

    @Then("the inputvalidator rejects")
    Document rejects() {
        return Document();
    }

}
