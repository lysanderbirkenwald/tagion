/// Module for handling callbacks from the hashgraph
module tagion.hashgraph.Refinement;

import tagion.hashgraph.RefinementInterface;
import tagion.crypto.Types : Pubkey;
import tagion.basic.Types : Buffer;
import tagion.hashgraph.Event;
import tagion.hashgraph.Round;
import tagion.utils.BitMask;
import tagion.hashgraph.HashGraph;
import tagion.hashgraph.HashGraphBasic;
import tagion.utils.StdTime;
import tagion.logger.Logger;
import tagion.hibon.HiBONRecord;
import tagion.hibon.Document;
import tagion.hibon.HiBON;

// std
import std.stdio;
import std.algorithm : map, filter, sort;
import std.array;
import tagion.utils.pretend_safe_concurrency;

@safe
class StdRefinement : Refinement {

    enum MAX_ORDER_COUNT = 10; /// Max recursion count for order_less function
    protected {
        HashGraph hashgraph;
    }

    void setOwner(HashGraph hashgraph)
    in (this.hashgraph is null)
    do {
        this.hashgraph = hashgraph;
    }

    Tid collector_service;
    void payload(immutable(EventPackage*) epack) {
        if (!epack.event_body.payload.empty) {
            // send to collector payload.

        }
    }

    void finishedEpoch(const(Event[]) events, const sdt_t epoch_time, const Round decided_round) {
        auto epoch_created = submask.register("epoch_creator/epoch_created");

        immutable epoch_events = events
            .map!((e) => e.event_package)
            .array;

        log(epoch_created, "epoch succesful", epoch_events);

    }

    void excludedNodes(ref BitMask excluded_mask) {
        // should be implemented
    }

    void epack(immutable(EventPackage*) epack) {
        // log.trace("epack.event_body.payload.empty %s", epack.event_body.payload.empty);
    }


    version(none)
    void epoch(Event[] event_collection, const(Round) decided_round) {

        const famous_witnesses = decided_round
                                        ._events
                                        .filter!(e => e !is null)
                                        .filter!(e => decided_round.famous_mask[e.node_id]);

        import std.bigint; 

        struct PseudoTime {
            BigInt numerator;
            BigInt denominator;

            this(int num, int denom) {
                numerator = BigInt(num);
                denominator = BigInt(denom);
            }
            
            int[] opBinary(string op : "+")(int rhs)
            {
                BigInt d = gcd(denominator, rhs.denominator);
                return PseudoTime(rhs.denominator/d*numerator+denominator/d*rhs.numerator,denominator/d*rhs.denominator);
            }
        }

        PseudoTime calc_pseudo_time(Event event) {
            // famous_witnesses
            //     .map!(e => e[]
            //                 .until!(e => e._youngest_son_ancestor[e.node].));
        }
    }

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
            if (a.received_order is b.received_order) {
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
            return a.received_order < b.received_order;
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
