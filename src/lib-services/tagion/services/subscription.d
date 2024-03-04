/// Service for publishing event subscription
module tagion.services.subscription;
@safe:

import core.time : msecs;
import nngd;
import std.array;
import std.format;
import std.variant;
import tagion.actor;
import tagion.communication.HiRPC;
import tagion.hibon.Document;
import tagion.hibon.HiBON;
import tagion.hibon.HiBONRecord;
import tagion.logger;
import tagion.logger.LogRecords;
import tagion.services.exception;

/// Options for the subscription service
struct SubscriptionServiceOptions {
    import tagion.utils.JSONCommon;

    string tags; /// List of tags that should be enabled seperated by a ','
    string address; /// The address which the service should pubish events on

    void setDefault() nothrow {
        import tagion.services.options : contract_sock_addr;

        address = contract_sock_addr("SUBSCRIPTION_");
    }

    uint sendtimeout = 1000;
    uint sendbufsize = 4096;
    mixin JSONCommon;
}

/// The package which is published over the subscription socket
@recordType("sub_payload")
struct SubscriptionPayload {
    @label("topic") string topic_name;
    @label("task") string task_name;
    @label("symbol") string symbol_name;
    @label("data") Document data;

    mixin HiBONRecord!(q{
            this(LogInfo info, const(Document) data) {
                this.topic_name = info.topic_name;
                this.task_name = info.task_name;
                this.symbol_name = info.symbol_name;
                this.data = data;
            }
    });
}

///
struct SubscriptionService {
    void task(immutable(SubscriptionServiceOptions) opts) @trusted {
        log.registerSubscriptionTask(thisActor.task_name);
        log("Subscribing to tags %s", opts.tags);
        foreach (tag; opts.tags.split(',')) {
            submask.subscribe(tag);
        }
        scope (exit) {
            foreach (tag; opts.tags.split(',')) {
                submask.unsubscribe(tag);
            }
        }
        log("Subscribed to tags");

        NNGSocket sock = NNGSocket(nng_socket_type.NNG_SOCKET_PUB);
        sock.sendtimeout = opts.sendtimeout.msecs;
        sock.sendbuf = opts.sendbufsize;

        HiRPC hirpc;

        int rc = sock.listen(opts.address);
        check(rc == 0, format("Could not listen to url %s: %s", opts.address, rc.nng_errstr));

        log("Publishing on %s", opts.address);

        void receiveSubscription(LogInfo info, const(Document) data) @trusted {
            immutable(ubyte)[] payload;

            payload = cast(immutable(ubyte)[])(info.topic_name ~ info.task_name ~ '\0');

            auto hibon = SubscriptionPayload(info, data);
            auto sender = hirpc.log(hibon);
            payload ~= sender.toDoc.serialize;

            rc = sock.send(payload);
        }

        run(&receiveSubscription);
    }
}
