/// HashGraph basic support functions
module tagion.hashgraphview.EventView;

import std.exception;

import tagion.hashgraph.Event;
import tagion.hibon.HiBONRecord;
import tagion.basic.Types : Buffer;
import tagion.hashgraph.HashGraphBasic : isMajority;

@recordType("node_amount")
struct NodeAmount {
    long nodes;
    mixin HiBONRecord!(q{
            this(long nodes) @safe pure nothrow {
                this.nodes = nodes;
            }
    });
}

/// EventView is used to store event has a
@recordType("event_view")
struct EventView {
    enum eventsName = "$events";
    uint id;
    @label("$m") @optional @(filter.Initialized) uint mother;
    @label("$f") @optional @(filter.Initialized) uint father;
    @label("$n") size_t node_id;
    @label("$a") int altitude;
    @label("$o") long order;
    @label("$r") long round;
    @label("$rec") long round_received;
    @label("$w") @optional @(filter.Initialized) bool witness;
    @label("$i") @optional @(filter.Initialized) bool intermediate;
    //    @label("$I") @reserve @optional @(filter.Initialized) uint[] intermediate_event_ids; 
    @label("$famous") @optional @(filter.Initialized) bool famous;
    @label("$error") @optional bool error;
    @label("$seen") @optional Buffer seen;
    @label("$strong") @optional Buffer strongly_seen; /// Witness seen strongly in previous round
    @label("$intermediate") @optional Buffer intermediate_seen;
    @label("$yes") @optional uint yes_votes; /// Famous yes votes    
    @label("$no") @optional uint no_votes; /// Famous no votes    
    @label("$voted") @optional Buffer voted; /// Witness which has voted    
    @label("$decided") @optional @(filter.Initialized) bool decided; /// Witness decided
//  @label("$strongx") @reserve @optional Buffer[] strongly_seen_matrix;
    bool father_less;

    mixin HiBONRecord!(q{
        this(const Event event, const size_t relocate_node_id=size_t.max) @safe pure nothrow {
            import std.algorithm : each;
            id=event.id;
            if (event.isGrounded) {
                mother = father = uint.max;
            }
            else {
                if (assumeWontThrow(event.mother)) {
                    mother=assumeWontThrow(event.mother).id;
                }
                if (assumeWontThrow(event.father)) {
                    father=assumeWontThrow(event.father).id;
                }
            }
            error=event.error;
            node_id=(relocate_node_id is size_t.max)?event.node_id:relocate_node_id;
            altitude=event.altitude;
            order=event.order;
            witness=event.isWitness;
            if (witness) {
                famous = event.isFamous;
            }
            round=(event.hasRound)?event.round.number:event.round.number.min;
            father_less=event.isFatherLess;
            round_received=(event.round_received)?event.round_received.number:long.min;
            import tagion.hashgraph.Event2;
            const event2=cast(const(Event2))event;
            if (event2 !is null) {
                intermediate=event2._intermediate_event;
                seen=event2._witness_seen_mask.bytes;   
                intermediate_seen=event2._intermediate_seen_mask.bytes;
                if (event2.isWitness) {
                    auto witness=cast(const(Event2.Witness2))(event._witness);
                    strongly_seen=witness.previous_strongly_seen_mask.bytes;
                    yes_votes = witness.yes_votes;
                    no_votes = witness.no_votes;
                    famous = isMajority(yes_votes, event2.round.events.length); 
                    voted = witness.has_voted_mask.bytes; 
                    decided = witness.decided;
                }
            }
            
        }
    });
}

import tagion.hashgraph.HashGraph;
import tagion.crypto.Types : Pubkey;

@safe
void fwrite(ref const(HashGraph) hashgraph, string filename, Pubkey[string] node_labels = null) {
    import std.algorithm : sort, filter, each;
    import std.stdio;
    import tagion.hashgraphview.EventView;
    import tagion.hibon.HiBONFile : fwrite;

    File graphfile = File(filename, "w");

    size_t[Pubkey] node_id_relocation;
    if (node_labels.length) {
        // assert(node_labels.length is _nodes.length);
        auto names = node_labels.keys;
        names.sort;
        foreach (i, name; names) {
            node_id_relocation[node_labels[name]] = i;
        }

    }

    EventView[size_t] events;
    /* auto events = new HiBON; */
    (() @trusted {
        foreach (n; hashgraph.nodes) {
            const node_id = (node_id_relocation.length is 0) ? size_t.max : node_id_relocation[n.channel];
            n[]
                .filter!((e) => !e.isGrounded)
                .each!((e) => events[e.id] = EventView(e, node_id));
        }
    })();

    graphfile.fwrite(NodeAmount(hashgraph.node_size));
    foreach (e; events) {
        graphfile.fwrite(e);
    }
}
