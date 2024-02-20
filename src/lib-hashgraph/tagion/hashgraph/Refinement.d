/// Module for handling callbacks from the hashgraph
module tagion.hashgraph.Refinement;

import tagion.basic.Debug;
import tagion.basic.Types : Buffer;
import tagion.crypto.Types : Pubkey;
import tagion.hashgraph.Event;
import tagion.hashgraph.HashGraph;
import tagion.hashgraph.HashGraphBasic;
import tagion.hashgraph.RefinementInterface;
import tagion.hashgraph.Round;
import tagion.hibon.Document;
import tagion.hibon.HiBON;
import tagion.hibon.HiBONRecord;
import tagion.logger.Logger;
import tagion.services.messages : consensusEpoch;
import tagion.utils.BitMask;
import tagion.utils.StdTime;

// std
import std.algorithm : filter, map, reduce, sort, until;
import std.array;
import std.stdio;
import tagion.hibon.HiBONRecord;
import tagion.script.standardnames;
import tagion.services.options : TaskNames;
import tagion.utils.pretend_safe_concurrency;

@safe
@recordType("finishedEpoch")
struct FinishedEpoch {
    @label("events") const(EventPackage)[] events;
    @label(StdNames.time) sdt_t time;
    @label("epoch") long epoch;
    mixin HiBONRecord!(q{
        this(const(Event)[] events, sdt_t time, long epoch) pure {
            this.events = events
                .map!((e) => *(e.event_package))
                .array;

            this.time = time;
            this.epoch = epoch;
        }
    });
}

@safe
class StdRefinement : Refinement {

    static Topic epoch_created = Topic("epoch_creator/epoch_created");

    enum MAX_ORDER_COUNT = 10; /// Max recursion count for order_less function
    protected {
        HashGraph hashgraph;
        TaskNames task_names;
    }

    void setOwner(HashGraph hashgraph)
    in (this.hashgraph is null)
    do {
        this.hashgraph = hashgraph;
    }

    void setTasknames(TaskNames task_names) {
        this.task_names = task_names;
    }

    Tid collector_service;
    void payload(immutable(EventPackage*) epack) {
        if (!epack.event_body.payload.empty) {
            // send to collector payload.

        }
    }

    void finishedEpoch(
            const(Event[]) events,
            const sdt_t epoch_time,
            const Round decided_round) {
        auto event_payload = FinishedEpoch(events, epoch_time, decided_round.number);

        log.event(epoch_created, "epoch_succesful", event_payload);

        if (task_names is TaskNames.init) {
            return;
        }

        immutable(EventPackage*)[] epacks = events
            .map!((e) => e.event_package)
            .array;

        auto transcript_tid = locate(task_names.transcript);
        if (transcript_tid !is Tid.init) {
            transcript_tid.send(consensusEpoch(), epacks, cast(immutable(long)) decided_round.number, epoch_time);
        }
    }

    void excludedNodes(ref BitMask excluded_mask) {
        // should be implemented
    }

    void epack(immutable(EventPackage*) epack) {
        // log.trace("epack.event_body.payload.empty %s", epack.event_body.payload.empty);
    }

    void epoch(Event[] event_collection, const(Round) decided_round) {

        import std.bigint;
        import std.numeric : gcd;
        import std.range : back, retro, tee;

        pragma(msg, "fixme(bbh): move pseudotime out and add function labels");
        struct PseudoTime {
            BigInt num; //fraction representing the avg received round
            BigInt denom;
            BigInt order; //sum of received orders
            sdt_t time; //avg received time

            this(BigInt num, BigInt denom, BigInt order, long time) {
                this.num = num;
                this.denom = denom;
                this.order = order;
                this.time = time;
            }

            this(int num, int denom, int order, sdt_t time, long round_number, ulong witness_count) {
                this.num = BigInt(num + denom * round_number);
                this.denom = BigInt(denom * witness_count);
                this.order = BigInt(order);
                this.time = time / witness_count;
            }

            PseudoTime opBinary(string op)(PseudoTime other) if (op == "+") {
                BigInt d = gcd(denom, other.denom);
                return PseudoTime(other.denom / d * num + denom / d * other.num,
                        denom / d * other.denom,
                        order + other.order,
                        time + other.time);
            }
        }

        const famous_witnesses = decided_round
            ._events
            .filter!(e => e !is null)
            .filter!(e => decided_round.famous_mask[e.node_id])
            .array;

        PseudoTime calc_pseudo_time(Event event) {
            auto receivers = famous_witnesses
                .map!(e => e[].until!(e => !e.sees(event))
                        .array.back);

            return receivers.map!(e => PseudoTime(e.pseudo_time_counter,
                    (e[].retro.filter!(e => e._witness)
                    .front._mother.pseudo_time_counter + 1),
                    e.order,
                    e.event_body.time,
                    e.round.number,
                    decided_round.famous_mask.count))
                .array
                .reduce!((a, b) => a + b);
        }

        bool order_less(Event a, Event b) {
            PseudoTime at = calc_pseudo_time(a);
            PseudoTime bt = calc_pseudo_time(b);

            if (at.num * bt.denom == at.denom * bt.num) {
                if (at.order == bt.order) {
                    if (a.order == b.order) {
                        return a.fingerprint < b.fingerprint;
                    }
                    return a.order < b.order;
                }
                return at.order < bt.order;
            }
            return at.num * bt.denom < at.denom * bt.num;
        }

        sdt_t[] times;
        auto events = event_collection
            .tee!((e) => times ~= e.event_body.time)
            .filter!((e) => !e.event_body.payload.empty)
            .array
            .sort!((a, b) => order_less(a, b))
            .release;

        times.sort;
        const epoch_time = times[times.length / 2];

        version (EPOCH_LOG) {
            log.trace("%s Epoch round %d event.count=%d witness.count=%d event in epoch=%d time=%s",
                    hashgraph.name, decided_round.number,
                    Event.count, Event.Witness.count, events.length, epoch_time);
        }
        log.trace("event.count=%d witness.count=%d event in epoch=%d", Event.count, Event.Witness.count, events.length);

        finishedEpoch(events, epoch_time, decided_round);

        excludedNodes(hashgraph._excluded_nodes_mask);
    }

    version (none) //SHOULD NOT BE DELETED SO WE CAN REVERT TO OLD ORDERING IF NEEDED
    void epoch(Event[] event_collection, const(Round) decided_round) {
        import std.algorithm;
        import std.range;

        bool order_less(const Event a, const Event b, const(int) order_count) @safe {
            bool rare_less(Buffer a_print, Buffer b_print) {
                // rare_order_compare_count++;
                pragma(msg, "review(cbr): Concensus order changed");
                return a_print < b_print;
            }

            if (order_count < 0) {
                return rare_less(a.fingerprint, b.fingerprint);
            }
            if (a.order is b.order) {
                if (a.father && b.father) {
                    return order_less(a.father, b.father, order_count - 1);
                }
                if (a.father) {
                    return true;
                }
                if (b.father) {
                    return false;
                }

                if (!a.isFatherLess && !b.isFatherLess) {
                    return order_less(a.mother, b.mother, order_count - 1);
                }

                return rare_less(a.fingerprint, b.fingerprint);
            }
            return a.order < b.order;
        }

        sdt_t[] times;
        auto events = event_collection
            .filter!((e) => e !is null)
            .tee!((e) => times ~= e.event_body.time)
            .filter!((e) => !e.event_body.payload.empty)
            .array
            .sort!((a, b) => order_less(a, b, MAX_ORDER_COUNT))
            .release;
        times.sort;
        const mid = times.length / 2 + (times.length % 1);
        const epoch_time = times[mid];

        log.trace("%s Epoch round %d event.count=%d witness.count=%d event in epoch=%d time=%s",
                hashgraph.name, decided_round.number,
                Event.count, Event.Witness.count, events.length, epoch_time);

        finishedEpoch(events, epoch_time, decided_round);

        excludedNodes(hashgraph._excluded_nodes_mask);
    }

}

@safe
struct RoundFingerprint {
    Buffer[] fingerprints;
    mixin HiBONRecord;
}

@safe
const(RoundFingerprint) hashLastDecidedRound(const Round last_decided_round) pure nothrow {
    import std.algorithm : filter;

    RoundFingerprint round_fingerprint;
    round_fingerprint.fingerprints = last_decided_round.events
        .filter!(e => e !is null)
        .map!(e => cast(Buffer) e.event_package.fingerprint)
        .array
        .sort
        .array;
    return round_fingerprint;
}
