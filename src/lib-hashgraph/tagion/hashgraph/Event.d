/// HashGraph Event
module tagion.hashgraph.Event;

//import std.stdio;

import std.datetime; // Date, DateTime
import std.algorithm.iteration : cache, each, filter, fold, joiner, map, reduce;
import std.algorithm.searching : all, any, canFind, count, until;
import std.algorithm.sorting : sort;
import std.array : array;
import std.conv;
import std.format;
import std.range;
import std.range : enumerate, tee;
import std.range.primitives : isBidirectionalRange, isForwardRange, isInputRange, walkLength;
import std.stdio;
import std.traits : ReturnType, Unqual;
import std.traits;
import std.typecons;
import tagion.basic.Types : Buffer;
import tagion.basic.basic : EnumText, basename, buf_idup, this_dot;
import tagion.crypto.Types : Pubkey;
import tagion.hashgraph.HashGraph : HashGraph;
import tagion.hashgraph.HashGraphBasic : EvaPayload, EventBody, EventPackage, Tides, higher, isAllVotes, isMajority;
import tagion.hashgraph.Round;
import tagion.monitor.Monitor : EventMonitorCallbacks;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBON : HiBON;
import tagion.hibon.HiBONRecord;
import tagion.logger.Logger;
import tagion.utils.BitMask : BitMask;
import tagion.utils.Miscellaneous;
import tagion.utils.StdTime;
import tagion.basic.Debug;

/// HashGraph Event
@safe
class Event {
    package static bool scrapping;

    import tagion.basic.ConsensusExceptions;

    alias check = Check!EventConsensusException;
    protected static uint _count;

    package int pseudo_time_counter;

    package {
        // This is the internal pointer to the connected Event's
        Event _mother;
        Event _father;
        Event _daughter;
        Event _son;

        long _order;
        // The withness mask contains the mask of the nodes
        // Which can be seen by the next rounds witness
        BitMask _round_seen_mask;
    }
    Witness _witness;

    BitMask _witness_seen_mask; /// Witness seen in privious round
    BitMask _intermediate_seen_mask;
    bool _intermediate_event;
    @nogc
    static uint count() nothrow {
        return _count;
    }

    bool error;
    bool top;
    Topic topic = Topic("hashgraph_event");

    /**
     * Builds an event from an eventpackage
     * Params:
     *   epack = event-package to build from
     *   hashgraph = the hashgraph which produce the event
     */
    package this(
            immutable(EventPackage)* epack,
            HashGraph hashgraph,
            const uint check_graphtype = 0
    )
    in (epack !is null)
    do {
        event_package = epack;
        this.id = hashgraph.next_event_id;
        this.node_id = hashgraph.getNode(channel).node_id;
        _count++;
        _witness_seen_mask[node_id] = true;
    }

    protected ~this() {
        _count--;
    }

    invariant {
        if (!scrapping && this !is null) {
            if (_mother) {
                // assert(!_witness_mask[].empty);
                assert(_mother._daughter is this);
                assert(
                        event_package.event_body.altitude - _mother
                        .event_package.event_body.altitude is 1);
                assert(_order is long.init || (_order - _mother._order > 0));
            }
            if (_father) {
                pragma(msg, "fixme(bbh) this test should be reimplemented once new witness def works");
                // assert(_father._son is this, "fathers is not me");
                assert(_order is long.init || (_order - _father._order > 0));
            }
        }
    }

    /**
     * The witness event will point to the witness object
     * This object contains information about the voting etc. for the witness event
     */
    @safe
    class Witness {
        protected static uint _count;
        @nogc static uint count() nothrow {
            return _count;
        }

        //private {
        //BitMask _vote_on_earliest_witnesses;
        //BitMask _prev_strongly_seen_witnesses;
        //BitMask _prev_seen_witnesses;
        //}

        // BitMask[] strongly_seen_matrix;
        // BitMask strongly_seen_mask;
        //current_event.Event[] _intermediate_events;
        //private {
        BitMask _intermediate_event_mask;
        BitMask _previous_strongly_seen_mask;
        uint _yes_votes;
        BitMask _has_voted_mask; /// Witness in the next round which has voted
        //uint _no_votes;
        //}

        final size_t votes() const pure nothrow @nogc {
            return _has_voted_mask.count;
        }
        final const(BitMask) previous_strongly_seen_mask() const pure nothrow @nogc {
            return _previous_strongly_seen_mask;
        }

        final const(BitMask) intermediate_event_mask() const pure nothrow @nogc {
            return _intermediate_event_mask;
        }

        final uint yes_votes() const pure nothrow @nogc {
            return _yes_votes;
        }

        final uint no_votes() const pure nothrow @nogc {
            return cast(uint)(_has_voted_mask.count) - _yes_votes;
        }

        final const(BitMask) has_voted_mask() const pure nothrow @nogc {
            return _has_voted_mask;
        }

        private void voteYes(const size_t node_id) pure nothrow {
            if (!_has_voted_mask[node_id]) {
                _yes_votes++;
                _has_voted_mask[node_id] = true;
            }
        }

        private void voteNo(const size_t node_id) pure nothrow {
            if (!_has_voted_mask[node_id]) {
                _has_voted_mask[node_id] = true;
            }
        }

        bool votedNo() const pure nothrow @nogc {
            return isMajority(no_votes, this.outer._round.events.length);
        }

        bool votedYes() const pure nothrow @nogc {
            return isMajority(_yes_votes, this.outer._round.events.length);
        }

        alias isFamous = votedYes;
        bool decided() const pure nothrow @nogc {
            const voted = _has_voted_mask.count;
            const N = this.outer._round.events.length;

            if (isMajority(voted, N)) {
                if (isMajority(yes_votes, N) || isMajority(no_votes, N)) {
                    return true;
                }
                const voters = this.outer._round.next.voters; //_events.filter!(e => e !is null).count;
                if (voters == voted) {
                    //const can=this.outer._round.next.has_feature_famous_round;
                    
                    //if (can) {
                    //    return false;
                    
                    const votes_left = long(N) - long(voted);
                    return !isMajority(votes_left + yes_votes, N);
                    //return (yes_votes > no_votes) ?
                    //    !isMajority(votes_left + yes_votes, N) : !isMajority(votes_left + no_votes, N);
                //}
        }
            }
            return false;
        }

        void display_decided() const pure nothrow @nogc {
            const voters=(this.outer.round.next)? this.outer._round.next.events.filter!(e => e !is null).count:0;
            const voted = _has_voted_mask.count;
            const N = this.outer._round.events.length;
            const votes_left = long(N) - long(voted);
            __write("votes=%d voters=%d N=%d votes_left=%d %s %s %s %s %s yes=%d no=%d not_yes=%d not_no=%d decided=%s",
                    voted, voters, N, votes_left,

                    isMajority(voted, N),
                    isMajority(yes_votes, N),
                    isMajority(no_votes, N),
                    !isMajority(votes_left + yes_votes, N),
                    !isMajority(votes_left + no_votes, N),
                    yes_votes, no_votes,
                    votes_left + yes_votes,
                    votes_left + no_votes,
                    decided);
        }

        //bool famous;
        /**
         * Contsruct a witness of an event
         * Params:
         *   owner_event = the event which is voted to be a witness
         *   seeing_witness_in_previous_round_mask = The witness seen from this event to the previous witness.
         */
        private this() nothrow {
            auto witness_event = this.outer;
            _count++;
            witness_event._witness = this;
            if (witness_event.father_witness_is_leading) {
                _previous_strongly_seen_mask = witness_event._mother._intermediate_seen_mask |

                    _father._round._events[_father.node_id]._witness
                        ._previous_strongly_seen_mask;

            }
            else {
                //if (_mother) {
                _previous_strongly_seen_mask = witness_event._intermediate_seen_mask.dup;
            }
            //_intermediate_events.length = hashgraph.node_size;
            _intermediate_event_mask[node_id] = true;

            witness_event._intermediate_seen_mask.clear;
            witness_event._intermediate_event = false;
            witness_event._witness_seen_mask.clear;
            witness_event._witness_seen_mask[witness_event.node_id] = true;
        }

        bool hasVoted() const pure nothrow {
            return this.outer._round !is null;
        }

        void vote(HashGraph hashgraph) nothrow
        in ((!hasVoted), "This witness has already voted")
        do {
            auto witness_event = this.outer;
            hashgraph._rounds.set_round(witness_event);
            /// Counting yes/no votes from this witness to witness in the previous round
            if (witness_event.round.previous) {
                auto previous_witness_events = witness_event._round.previous._events;
                foreach (n, previous_witness_event; previous_witness_events) {
                    //auto previous_witness_event = previous_witness_events[n];
                    if (previous_witness_event) {
                        auto vote_for_witness = previous_witness_event._witness;
                        const seen_strongly = _previous_strongly_seen_mask[n];
                        if (seen_strongly) {
                            vote_for_witness.voteYes(witness_event.node_id);
                        }
                        else {
                            vote_for_witness.voteNo(witness_event.node_id);
                        }
                        Event.callbacks.connect(previous_witness_event);
                    }
                }
            }
            // Counting no-votes from witness in the next round
            // which was created before this witness
            if (witness_event.round.next) {
                auto next_witness_events = witness_event.round.next.events;
                next_witness_events
                    .filter!(vote_from_event => vote_from_event !is null)
                    .map!(vote_from_event => vote_from_event._witness)
                    .filter!(vote_from_witness => !vote_from_witness._previous_strongly_seen_mask[witness_event.node_id])
                    .each!(vote_from_witness => voteNo(vote_from_witness.outer.node_id));
            }
        }

        ~this() {
            _count--;
        }

    }

    bool father_witness_is_leading() const pure nothrow {
        return _father &&
            higher(_father._round.number, _mother._round.number) &&
            _father._round._events[_father.node_id];
    }

    bool calc_strongly_seen2(HashGraph hashgraph) const pure nothrow
    in (_father, "Calculation of strongly seen only makes sense if we have a father")
    do {
        if (father_witness_is_leading) {
            return true;
        }
        const majority_intermediate_seen = isMajority(_intermediate_seen_mask, hashgraph);
        if (majority_intermediate_seen) {
            const vote_strongly_seen = _mother._round
                ._events
                .filter!(e => e !is null)
                .map!(e => e._witness)
                .map!(w => w._intermediate_event_mask[node_id])
                .count;
            return isMajority(vote_strongly_seen, hashgraph.node_size);
        }
        return false;
    }

    static EventMonitorCallbacks callbacks;

    // The altitude increases by one from mother to daughter
    immutable(EventPackage*) event_package;

    /**
  * The rounds see forward from this event
  * Returns:  round seen mask
  */
    const(BitMask) round_seen_mask() const pure nothrow @nogc {
        return _round_seen_mask;
    }

    Round _round; /// The where the event has been created

    package {
        BitMask _round_received_mask; /// Voting mask for the received rounds
    }
    protected {
        Round _round_received; /// The round in which the event has been voted to be received
    }

    invariant {
        if (_round_received !is null && _round_received.number > 1 && _round_received.previous !is null) {

            assert(_round_received.number == _round_received.previous.number + 1, format("Round was not added by 1: current: %s previous %s", _round_received
                    .number, _round_received.previous.number));
        }
    }

    /**
     * Attach the mother round to this event
     * Params:
     *   hashgraph = the graph which produces this event
     */
    package void attach_round(HashGraph hashgraph) pure nothrow {
        if (!_round) {
            _round = _mother._round;
        }
    }

    immutable uint id;

    /**
    *  Makes the event a witness  
    */
    void witness_event(HashGraph hashgraph) nothrow
    in (!_witness, "Witness has already been set")
    out {
        assert(_witness, "Witness should be set");
    }
    do {
        new Witness;
    }

    immutable size_t node_id; /// Node number of the event

    void initializeOrder() pure nothrow @nogc {
        if (order is long.init) {
            _order = -1;
        }
    }

    /**
      * Connect the event to the hashgraph
      * Params:
      *   hashgraph = event owner 
      */
    void connect(HashGraph hashgraph)
    in {
        assert(hashgraph.areWeInGraph);
    }
    out {
        assert(event_package.event_body.mother && _mother || !_mother);
        assert(event_package.event_body.father && _father || !_father);
    }
    do {
        if (connected) {
            return;
        }
        scope (exit) {
            if (_mother) {
                Event.check(this.altitude - _mother.altitude is 1,
                        ConsensusFailCode.EVENT_ALTITUDE);
                Event.check(channel == _mother.channel,
                        ConsensusFailCode.EVENT_MOTHER_CHANNEL);
            }
            hashgraph.front_seat(this);
            Event.callbacks.connect(this);
            hashgraph.refinement.payload(event_package);
        }

        _mother = hashgraph.register(event_package.event_body.mother);
        if (!_mother) {
            if (!isEva && !hashgraph.joining && !hashgraph.rounds.isEventInLastDecidedRound(this)) {
                check(false, ConsensusFailCode.EVENT_MOTHER_LESS);
            }
            //   calc_strongly_seen(hashgraph);
            return;
        }

        check(!_mother._daughter, ConsensusFailCode.EVENT_MOTHER_FORK);
        _mother._daughter = this;
        _father = hashgraph.register(event_package.event_body.father);
        _order = ((_father && higher(_father.order, _mother.order)) ? _father.order : _mother.order) + 1;
        _witness_seen_mask |= _mother._witness_seen_mask;
        _intermediate_seen_mask |= _mother._intermediate_seen_mask;
        //hashgraph._rounds._round(this);
        if (_father) {
            check(!_father._son, ConsensusFailCode.EVENT_FATHER_FORK);
            _father._son = this;
            BitMask new_witness_seen;
            if (_father._round.number == _mother._round.number) {
                _witness_seen_mask |= _father._witness_seen_mask;
                _intermediate_seen_mask |= _father._intermediate_seen_mask;
                new_witness_seen = _father._witness_seen_mask - _mother
                    ._witness_seen_mask;
            }
            else {
                new_witness_seen = _witness_seen_mask;
            }
            if (!new_witness_seen[].empty) {
                _intermediate_event = true;
                _intermediate_seen_mask[node_id] = true;
                auto max_round = maxRound;
                new_witness_seen[]
                    .filter!((n) => max_round._events[n]!is null)
                    .map!((n) => max_round._events[n]._witness)
                    .filter!((witness) => witness._intermediate_event_mask[node_id])
                    .each!((witness) => witness._intermediate_event_mask[node_id] = true);
            }
            const strongly_seen = calc_strongly_seen2(hashgraph);
            if (strongly_seen) {
                auto witness = new Witness;
                witness.vote(hashgraph);
                hashgraph._rounds.check_decide_round;
                return;
            }
        }
        hashgraph._rounds.set_round(this);
    }

    Round maxRound() nothrow {
        if (_round) {
            return _round;
        }
        if (_father && higher(_father._round.number, _mother._round.number)) {
            return _father._round;
        }
        return _mother._round;
    }

    /**
     * Disconnect this event from hashgraph
     * Used to remove events which are no longer needed 
     * Params:
     *   hashgraph = event owner
     */
    final package void disconnect(HashGraph hashgraph) nothrow @trusted
    in {
        assert(!_mother, "Event with a mother can not be disconnected");
       // assert(hashgraph.graphtype == 0);
    }
    do {
        hashgraph.eliminate(fingerprint);
        if (_witness) {
            _round.remove(this);
            _witness.destroy;
            _witness = null;
        }
        if (_daughter) {
            _daughter._mother = null;
        }
        if (_son) {
            _son._father = null;
        }
        _daughter = _son = null;
    }

    const bool sees(Event b) pure {

        assert(0);
        version (none) {
            if (_youngest_son_ancestors[b.node_id] is null) {
                return false;
            }
            if (!higher(b.order, _youngest_son_ancestors[b.node_id].order)) {
                return true;
            }
            if (node_id == b.node_id && !higher(b.order, order)) {
                return true;
            }

            auto see_through_candidates = b[].retro
                .until!(e => e.pseudo_time_counter != b.pseudo_time_counter)
                .filter!(e => e._son)
                .map!(e => e._son);

            foreach (e; see_through_candidates) {
                if (_youngest_son_ancestors[e.node_id] is null) {
                    continue;
                }
                if (!higher(e.order, _youngest_son_ancestors[e.node_id].order)) {
                    return true;
                }
            }
            return false;
        }
    }

    /**
     * Mother event
     * Throws: EventException if the mother has been grounded
     * Returns: mother event 
     */
    final const(Event) mother() const pure {
        Event.check(!isGrounded, ConsensusFailCode.EVENT_MOTHER_GROUNDED);
        return _mother;
    }

    /**
     * Mother event
     * Throws: EventException if the mother has been grounded
     * Returns: mother event 
     */
    final const(Event) father() const pure {
        Event.check(!isGrounded, ConsensusFailCode.EVENT_FATHER_GROUNDED);
        return _father;
    }

    void round_received(Round round_received) nothrow {
        _round_received = round_received;
    }

    bool isFamous() const pure nothrow {
        return isWitness && round.famous_mask[node_id];
    }

    package Witness witness() pure nothrow {
        return _witness;
    }

    @nogc pure nothrow const final {
        /**
     * The received round for this event
     * Returns: received round
     */
        const(Round) round_received() scope {
            return _round_received;
        }

        /**
      * The event-body from this event 
      * Returns: event-body
      */
        ref const(EventBody) event_body() {
            return event_package.event_body;
        }

        /**
     * Channel from which this event has received
     * Returns: channel
     */
        immutable(Pubkey) channel() {
            return event_package.pubkey;
        }

        /**
     * Get the mask of the received rounds
     * Returns: received round mask 
     */
        const(BitMask) round_received_mask() {
            return _round_received_mask;
        }

        /**
     * Checks if this event is the last one on this node
     * Returns: true if the event is in front
     */
        bool isFront() {
            return _daughter is null;
        }

        /**
     * Check if an event has around 
     * Returns: true if an round exist for this event
     */

        bool hasRound() {
            return (_round !is null);
        }

        /**
     * Round of this event
     * Returns: round
     */
        const(Round) round()
        out (result) {
            assert(result, "Round must be set before this function is called");
        }
        do {
            return _round;
        }
        /**
     * Gets the witness infomatioin of the event
     * Returns: 
     * if this event is a witness the witness is returned
     * else null is returned
     */
        const(Witness) witness() {
            return _witness;
        }

        bool isWitness() {
            return _witness !is null;
        }

        /**
         * Get the altitude of the event
         * Returns: altitude
         */
        immutable(int) altitude() scope {
            return event_package.event_body.altitude;
        }

        /**
          * Is this event owner but this node 
          * Returns: true if the event is owned
          */
        bool nodeOwner() const pure nothrow @nogc {
            return node_id is 0;
        }

        /**
         * Gets the event order number 
         * Returns: order
         */
        long order() const pure nothrow @nogc {
            return _order;
        }

        /**
       * Checks if the event is connected in the graph 
       * Returns: true if the event is corrected 
       */
        bool connected() const pure @nogc {
            return (_mother !is null);
        }

        /**
       * Gets the daughter event
       * Returns: the daughter
       */

        const(Event) daughter() {
            return _daughter;
        }

        /**
       * Gets the son of this event
       * Returns: the son
       */
        const(Event) son() {
            return _son;
        }
        /**
       * Get 
       * Returns: 
       */
        const(Document) payload() {
            return event_package.event_body.payload;
        }

        ref const(EventBody) eventbody() {
            return event_package.event_body;
        }

        //True if Event contains a payload or is the initial Event of its creator
        bool containPayload() {
            return !payload.empty;
        }

        // is true if the event does not have a mother or a father
        bool isEva()
        out (result) {
            if (result) {
                assert(event_package.event_body.father is null);
            }
        }
        do {
            return (_mother is null) && (event_package.event_body.mother is null);
        }

        /// A father less event is an event where the ancestor event is connect to an Eva event without an father event
        /// An Eva is is also defined as han father less event
        /// This also means that the event has not valid order and must not be included in the epoch order.
        bool isFatherLess() {
            return isEva || !isGrounded && (event_package.event_body.father is null) && _mother
                .isFatherLess;
        }

        bool isGrounded() {
            return (_mother is null) && (event_package.event_body.mother !is null) ||
                (_father is null) && (event_package.event_body.father !is null);
        }

        immutable(Buffer) fingerprint() {
            return event_package.fingerprint;
        }

        Range!true opSlice() {
            return Range!true(this);
        }
    }

    @nogc
    package Range!false opSlice() pure nothrow {
        return Range!false(this);
    }

    @nogc
    struct Range(bool CONST = true) {
        private Event current;
        static if (CONST) {
            this(const Event event) pure nothrow @trusted {
                current = cast(Event) event;
            }
        }
        else {
            this(Event event) pure nothrow {
                current = event;
            }
        }
        pure nothrow {
            bool empty() const {
                return current is null;
            }

            static if (CONST) {
                const(Event) front() const {
                    return current;
                }
            }
            else {
                ref Event front() {
                    return current;
                }
            }

            alias back = front;

            void popFront() {
                if (current) {
                    current = current._mother;
                }
            }

            void popBack() {
                if (current) {
                    current = current._daughter;
                }
            }

            Range save() {
                return Range(current);
            }
        }
    }

    static assert(isInputRange!(Range!true));
    static assert(isForwardRange!(Range!true));
    static assert(isBidirectionalRange!(Range!true));
}
