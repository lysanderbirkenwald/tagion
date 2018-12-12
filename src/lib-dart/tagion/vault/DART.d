module tagion.vault.DART;

import tagion.hashgraph.GossipNet : SecureNet;
import tagion.utils.BSON : HBSON, Document;
import tagion.hashgraph.ConsensusExceptions;

import tagion.Keywords;
import std.conv : to;

import std.stdio;
@safe
void check(bool flag, ConsensusFailCode code, string file = __FILE__, size_t line = __LINE__) {
    if (!flag) {
        throw new EventConsensusException(code, file, line);
    }
}

@safe
uint cover(const uint n) {
    uint local_cover(immutable uint width, immutable uint step) {
        immutable uint result=1 << width;
        if ( step != 0 ) {
            if ( result > n ) {
                if ( (result >> 1) >= n ) {
                    return local_cover(width-step, step >> 1);
                }
            }
            else if ( result < n ) {
                return local_cover(width+step, step >> 1);
            }
        }
        return result;
    }
    immutable width=(uint.sizeof*8) >> 1;
    return local_cover(width, width >> 1);
}

unittest {
    assert(cover(0x1FFF) == 0x2000);
    assert(cover(0x1200) == 0x2000);
    assert(cover(0x210) == 0x400);
    assert(cover(0x1000) == 0x1000);
}

immutable(ubyte[]) sparsed_merkeltree(T)(SecureNet net, T[] table) {
    immutable(ubyte[]) merkeltree(T[] left, T[] right) {
        scope immutable(ubyte)[] _left_fingerprint;
        scope immutable(ubyte)[] _right_fingerprint;
        if ( (left.length == 1) && (right.length == 1 ) ) {
            auto _left=left[0];
            auto _right=right[0];
            if ( _left ) {
                _left_fingerprint=_left.fingerprint(net);
            }
            if ( _right ) {
                _right_fingerprint=_right.fingerprint(net);
            }
        }
        else {
            immutable left_mid=left.length >> 1;
            immutable right_mid=right.length >> 1;
            _left_fingerprint=merkeltree(left[0..left_mid], left[left_mid..$]);
            _right_fingerprint=merkeltree(right[0..right_mid], right[right_mid..$]);
        }
        if ( _left_fingerprint is null ) {
            return _right_fingerprint;
        }
        else if ( _right_fingerprint is null ) {
            return _left_fingerprint;
        }
        else {
            return net.calcHash(_left_fingerprint~_right_fingerprint);
        }
    }
    immutable mid=table.length >> 1;
    return merkeltree(table[0..mid], table[mid..$]);
}


@safe
class DART {
    private SecureNet _net;
    private ushort _from_sector;
    private ushort _to_sector;
    private Bucket[] _root_buckets;
    enum bucket_max=1 << (ubyte.sizeof*8);
    enum uint root_depth=cast(uint)ushort.sizeof;
    enum sector_max = ushort.max;

    this(SecureNet net, const ushort from_sector, const ushort to_sector) {
        _net=net;
        _from_sector=from_sector;
        _to_sector=to_sector;
        _root_buckets=new Bucket[calc_sector_size(_from_sector, _to_sector)];
    }

    ushort root_sector(immutable(ubyte[]) data) pure const nothrow {
        return data[1] | (data[0] << 8);
    }

    ushort sector_to_index(const ushort sector) {
        return (sector-_from_sector) & ushort.max;
    }

    void add(immutable(ubyte[]) data) {
        auto archive=new ArchiveTab(_net, data);
        immutable sector=root_sector(archive.fingerprint);
        if ( inRange(sector) ) {
            immutable index=sector_to_index(sector);
            if ( _root_buckets[index] is null ) {
                _root_buckets[index]=new Bucket(root_depth);
            }
            _root_buckets[index].add(_net, archive);
        }
    }

    void remove(immutable(ubyte[]) data) {
        auto archive=new ArchiveTab(_net, data);
        immutable sector=root_sector(archive.fingerprint);
        if ( inRange(sector) ) {
            immutable index=sector_to_index(sector);
            if ( _root_buckets[index] ) {
                Bucket.remove(_root_buckets[index], _net, archive);
            }
        }
    }

    ArchiveTab find(immutable(ubyte[]) key) {
        writeln("---- ----- ----");
        immutable sector=root_sector(key);
        if ( inRange(sector) ) {
            immutable index=sector_to_index(sector);
            if ( _root_buckets[index] ) {
                return _root_buckets[index].find(key);
            }
        }
        return null;
    }

    static class ArchiveTab {
        immutable(ubyte[])  data;
        immutable(ubyte[])  fingerprint;
        Document document() const {
            return Document(data);
        }
        this(SecureNet net, immutable(ubyte[]) data) {
            fingerprint=net.calcHash(data);
            this.data=data;
        }
        ubyte index(const uint depth) const pure {
            return fingerprint[depth];
        }
    }

    Bucket.Iterator iterator(ushort sector) {
        check(inRange(sector),  ConsensusFailCode.DART_ARCHIVE_SECTOR_NOT_FOUND);
        return _root_buckets[sector_to_index(sector)].iterator;
    }


    static class Bucket {
        private Bucket[] _buckets;
        private uint _bucket_size;
        private ArchiveTab _archive;
        immutable uint depth;
        immutable size_t init_size;
        immutable size_t extend;
        private immutable(ubyte)[]  _fingerprint;
        bool isBucket() const pure nothrow {
            return _buckets !is null;
        }

        uint index(const uint depth) const pure {
            if ( isBucket ) {
                return _buckets[0].index(depth);
            }
            else {
                return _archive.index(depth);
            }
        }

        private int find_bucket_pos(const int index)
            in {
                assert(index <= ubyte.max);
                assert(index >= 0);
            }
        do {
            int find_bucket_pos(immutable int search_j, immutable int division_j) {
                writefln("search_j=%d division_j=%d", search_j, division_j);
                if ( search_j < _bucket_size ) {
                    immutable search_index=_buckets[search_j].index(depth);
                    writefln("\tsearch_index=%x", _buckets[search_j].index(depth));
                    if ( index == search_index ) {
                        return search_j;
                    }
                    else if ( division_j > 0 ) {
                        if ( index < search_index ) {
                            return find_bucket_pos(search_j-division_j, division_j/2);
                        }
                        else if ( index > search_index ) {
                            return find_bucket_pos(search_j+division_j, division_j/2);
                        }
                    }
                }
                else if ( division_j > 0 ) {
                    return find_bucket_pos(search_j-division_j, division_j/2);
                }
                return search_j;
            }
            writefln("bucket_size=%d", _bucket_size);
            immutable start_j=cover(_bucket_size) >> 1;
            return find_bucket_pos(start_j, start_j);
        }


        static size_t calc_init_size(size_t depth) {
            switch ( depth ) {
            case 0, 1, 2:
                return 32;
                break;
            case 3:
                return 4;
                break;
            default:
                return 1;
            }
        }

        static size_t calc_extend(size_t depth) {
            switch ( depth ) {
            case 0, 1, 2:
                return 16;
                break;
            case 3:
                return 4;
                break;
            default:
                return 1;
            }
        }

        size_t extend_size() pure const nothrow {
            immutable size=_buckets.length+extend;
            return (size <= ubyte.max)?size:ubyte.max+1;
        }

        size_t grow() {
            if ( _bucket_size+1 <= _buckets.length ) {
                return _buckets.length;
            }
            else {
                return extend_size;
            }
        }

        private void opIndexAssign(Bucket b, const uint index) {
            immutable pos=find_bucket_pos(index);
            assert( _buckets[pos].index(depth) != index );
            if ( _buckets is null ) {
                _buckets=new Bucket[init_size];
            }
            if ( _bucket_size+1 < _buckets.length ) {
                _buckets[pos+1.._bucket_size+1]=_buckets[pos.._bucket_size];
                _buckets[pos]=b;
                _bucket_size++;
            }
            else {
                auto new_buckets=new Bucket[extend_size];
                new_buckets[0..pos]=_buckets[0..pos];
                new_buckets[pos+1.._bucket_size+1]=_buckets[pos.._bucket_size];
                new_buckets[pos]=b;
                _buckets=new_buckets;
                _bucket_size++;
            }
        }

        private this(immutable uint depth) {
            this.depth=depth;
            init_size=calc_init_size(depth);
            extend=calc_extend(depth);

        }

        // this(ArchiveTab archive, immutable uint depth) {
        //     this(depth);
        //     _archive=archive;
        // }

        this(Document doc, SecureNet net, immutable uint depth) {
            this(depth);
            if ( doc.hasElement(Keywords.buckets) ) {
                auto buckets_doc=doc[Keywords.buckets].get!Document;
                _buckets=new Bucket[buckets_doc.length];
                foreach(elm; buckets_doc[]) {
                    auto arcive_doc=elm.get!Document;
                    immutable index=elm.key.to!ubyte;
                    this[index]=new Bucket(arcive_doc, net, depth+1);
                }
            }
            else if (doc.hasElement(Keywords.tab)) {
                // Fixme check that the Doc is HBSON
                auto arcive_doc=doc[Keywords.tab].get!Document;
                _archive=new ArchiveTab(net, arcive_doc.data);
            }
        }

        HBSON toBSON() const {
            auto bson=new HBSON;
            if ( isBucket ) {
                auto buckets=new HBSON;
                foreach(i;0.._bucket_size) {
                    auto b=_buckets[i];
                    buckets[b.index(depth).to!string]=b.toBSON;
                }
                bson[Keywords.buckets]=buckets;
            }
            else if ( _archive ) {
                bson[Keywords.tab]=_archive.document;
            }
            return bson;
        }

        immutable(ubyte[]) serialize() const {
            return toBSON.serialize;
        }

        ArchiveTab find(immutable(ubyte[]) key) {
            writefln("find=%s %x depth=%d", key, key[depth], depth);
            if ( isBucket ) {
                immutable pos=find_bucket_pos(key[depth]);
                writefln("\t\tpos=%d bucket_size=%d depth=%d key=0x%x", pos, _bucket_size, depth, key[depth] );
                if ( (pos >= 0) && (pos < _bucket_size) && _buckets[pos] ) {
                    writefln("\t\tdepth=%d", _buckets[pos].depth);
                    return _buckets[pos].find(key);
                }
            }
            else if ( _archive && (_archive.fingerprint == key) ) {
                return _archive;
            }
            return null;
        }

        void add(SecureNet net, ArchiveTab archive) {
            _fingerprint=null;
            if ( isBucket ) {
                immutable pos=find_bucket_pos(archive.fingerprint[depth]);
                writefln("add bucket %s pos=%d index=%x bucket_size=%d", archive.data, pos, archive.fingerprint[depth], _bucket_size);
                if ( (pos >= 0) && (pos < _bucket_size) && _buckets[pos].isBucket ) {
                    _buckets[pos].add(net, archive);
                }
                else {
                    auto temp_bucket=new Bucket(depth);
                    temp_bucket.add(net, archive);
                    if (pos == _bucket_size) {
                        if ( _bucket_size+1 >= _buckets.length ) {
                            _buckets.length=extend_size;
                        }
                        _bucket_size++;
                        _buckets[pos]=temp_bucket;
                    }
                    else if ( pos < 0 ) {
                        Bucket[] new_buckets;
                        if ( _bucket_size+1 <= _buckets.length ) {
                            new_buckets.length=extend_size;
                        }
                        else {
                            new_buckets.length=_buckets.length;
                        }
                        new_buckets[0]=temp_bucket;
                        new_buckets[1.._bucket_size+1]=_buckets[0.._bucket_size];
                        _bucket_size++;
                        _buckets=new_buckets;
                    }
                    else {
                        writefln("_archive.fingerprint=%s archive.fingerprint=%s", _buckets[pos]._archive.fingerprint, archive.fingerprint);
                        check(_buckets[pos]._archive.fingerprint != archive.fingerprint,  ConsensusFailCode.DART_ARCHIVE_ALREADY_ADDED);
                        if ( _bucket_size+1 <= _buckets.length ) {
                            writefln("\tfit in the bucket pos=%d", pos);
                            foreach_reverse(i;pos.._bucket_size) {
                                writefln("\t\ti=%d bucket_size=%d", i, _bucket_size);
                                _buckets[i+1]=_buckets[i];
                            }
                            _buckets[pos]=temp_bucket;
                            _bucket_size++;
                        }
                        else {
                            writefln("\tExpand the  bucket");
                            auto new_buckets=new Bucket[extend_size];
                            new_buckets[0..pos]=_buckets[0..pos];
                            new_buckets[pos+1.._bucket_size+1]=_buckets[pos.._bucket_size];
                            new_buckets[pos]=temp_bucket;
                            _buckets=new_buckets;
                            _bucket_size++;
                        }
                    }
                }
            }
            else if ( _archive is null ) {
                writefln("add archive %s", archive.data);
                _archive=archive;
            }
            else {
                writefln("add to bucket %s", archive.data);
                if ( _archive.index(depth) == archive.index(depth) ) {
                    writefln("\tsame sub bucket %x", archive.index(depth));
                    _bucket_size=1;
                    _buckets=new Bucket[_bucket_size];
                    auto temp_bucket=new Bucket(depth+1);
                    temp_bucket.add(net, _archive);
                    temp_bucket.add(net, archive);
                    _buckets[0]=temp_bucket;
                }
                else {
                    writefln("\tdo %x %x d=%d", _archive.index(depth), archive.index(depth), depth);
                    import std.algorithm : max;
                    immutable min_init_size=max(2,init_size);
                    _bucket_size=2;
                    _buckets=new Bucket[min_init_size];
                    _buckets[0]=new Bucket(depth);
                    _buckets[1]=new Bucket(depth);
                    writefln("\t\t[0]=%x [1]=%x", _archive.index(depth), archive.index(depth));
                    if ( _archive.index(depth) < archive.index(depth) ) {
                        _buckets[0].add(net, _archive);
                        _buckets[1].add(net, archive);
                    }
                    else {
                        _buckets[1].add(net, _archive);
                        _buckets[0].add(net, archive);
                    }
                    _archive=null;
                }
            }
        }

        static void remove(ref Bucket bucket, SecureNet net, const ArchiveTab archive) {
            Bucket.remove(bucket, archive, 0);
        }

        @trusted
        private static void remove(ref Bucket bucket, const ArchiveTab archive, immutable uint level) {
            scope(success) {
                if ( bucket ) {
                    bucket._fingerprint=null;
                }
            }
            if ( bucket.isBucket ) {
                immutable index=archive.fingerprint[level];
                check(bucket._buckets[index] !is null, ConsensusFailCode.DART_ARCHIVE_DOES_NOT_EXIST);
                Bucket.remove(bucket._buckets[index], archive, level+1);
            }
            else {
                bucket.destroy;
                bucket=null;
            }
        }

        immutable(ubyte[]) fingerprint(SecureNet net) {
            if ( _fingerprint ) {
                return _fingerprint;
            }
            else if ( isBucket ) {
                scope auto temp_buckets=new Bucket[bucket_max];
                foreach(i;0.._bucket_size) {
                    auto b=_buckets[i];
                    temp_buckets[b.index(depth)]=b;
                }
                _fingerprint=sparsed_merkeltree(net, temp_buckets);
                return _fingerprint;
            }
            else {
                return _archive.fingerprint;
            }
        }

        // uint length() const pure nothrow {
        //     return _count;
        // }
        Iterator iterator() {
            return Iterator(this);
        }
        struct Iterator {
            static class BucketStack {
                Bucket bucket;
                ubyte pos;
                BucketStack stack;
                this(Bucket b) {
                    bucket=b;
                }
            }

            this(Bucket b) {
                _stack=new BucketStack(b);
            }

            private void push(ref BucketStack b, Bucket bucket) {
                auto top_stack=new BucketStack(bucket);
                top_stack.stack=_stack;
                _stack=top_stack;
            }

            private void pop(ref BucketStack b) {
                _stack=b.stack;
            }

            private BucketStack _stack;
            private Bucket _current;
            void popFront() {
                if ( _stack ) {
                    if ( _stack.bucket.isBucket ) {
                        if ( _stack.pos < _stack.bucket._bucket_size ) {
                            _current=_stack.bucket._buckets[_stack.pos];
                            _stack.pos++;
                            if ( _current.isBucket ) {
                                push(_stack, _current);
                                popFront;
                            }
                        }
                        else {
                            pop(_stack);
                            popFront;
                        }
                    }
                    else {
                        _current=_stack.bucket;
                        pop(_stack);
                    }
                }
            }

            bool empty() const pure nothrow {
                return _stack is null;
            }

            const(Bucket) front()
            in {
                if ( _current ) {
                    assert(!_current.isBucket, "Should be an archive tab not bucket");
                }
            }
            do {
                return _current;
            }
        }

    }

    unittest {
        import tagion.Base;
        import std.typecons;
        static class TestNet : BlackHole!SecureNet {
            override immutable(Buffer) calcHash(immutable(ubyte[]) data) inout {
                return data;
            }
        }

        immutable(ubyte[]) data(const ulong x) {
            import std.bitmanip;
            return nativeToBigEndian(x).idup;
        }

        import std.stdio;

        immutable(ulong[]) table=[
            // first RIM test (depth=2)
            0x20_21_10_30_40_50_80_90,
            0x20_21_11_30_40_50_80_90,
            0x20_21_12_30_40_50_80_90,
            0x20_21_0a_30_40_50_80_90,

            // Second Rim test (depth=3)
            0x20_21_20_30_40_50_80_90,
            0x20_21_20_31_40_50_80_90,
            0x20_21_20_34_40_50_80_90,
            0x20_21_20_20_40_50_80_90,
            0x20_21_20_32_40_50_80_90,

            // Add in first rim again
            0x20_21_21_30_40_50_80_90,

            ];


        void add_and_find_check(immutable(ulong[]) array) {
            auto net=new TestNet;
            auto dart=new DART(net, 0x1000, 0x2022);
            foreach(a; array) {
                dart.add(data(a));
                auto key=data(a);
                writefln("key=%s %x %x %s", key, a, dart.root_sector(key), dart.inRange(dart.root_sector(key)));
            }
            //    foreach(b; dart
            foreach(a; array) {
                auto d=dart.find(data(a));
                if ( d ) {
                    writefln("found %s", d.data);
                }
                else {
                    writefln("Not found! %016x", a);
                }
            }
        }

        // Add and find test
        { // First rim test one element
            writeln("###### Test 1 ######");
            add_and_find_check(table[0..1]);
        }
        { // First rim test two elements
            writeln("###### Test 2 ######");
            add_and_find_check(table[0..2]);
        }
        { // First rim test three elements
            writeln("###### Test 3 ######");
            add_and_find_check(table[0..3]);
        }
        { // First rim test four elements (insert an element before all others)
            writeln("###### Test 4 ######");
            add_and_find_check(table[0..4]);
        }

        { // Second rim test 2 elements
            writeln("###### Test 5 ######");
            add_and_find_check(table[4..6]);
        }

        { // Second rim test 3 elements
            writeln("###### Test 6 ######");
            add_and_find_check(table[4..7]);
        }

        { // Second rim test 4 elements (insert an element before all others)
            writeln("###### Test 7 ######");
            add_and_find_check(table[4..8]);
        }

        { // Second rim test 5 elements (insert an element in the middel)
            writeln("###### Test 8 ######");
            add_and_find_check(table[4..9]);
        }

        { // Second rim test 6 elements (Last elemen is added in the first rim)
            writeln("###### Test 9 ######");
//            add_and_find_check(table[4..10]);
//            add_and_find_check(table[7..10]);
            add_and_find_check(table[7..10]);
        }

}

    static uint calc_to_sector(const ushort from_sector, const ushort to_sector) pure nothrow {
        return to_sector+((from_sector >= to_sector)?sector_max:0);
    }

    static uint calc_sector_size(const ushort from_sector, const ushort to_sector) pure nothrow {
        immutable from=from_sector;
        immutable to=calc_to_sector(from_sector, to_sector);
        return to-from;
    }

    bool inRange(const ushort sector) const pure nothrow  {
        immutable ushort sector_origin=(sector-_from_sector) & ushort.max;
        immutable ushort to_origin=(_to_sector-_from_sector) & ushort.max;
        return ( sector_origin < to_origin );
    }

    unittest { // Check the inRange function
        import std.typecons : BlackHole;
        auto net=new BlackHole!SecureNet;

        enum from1=0x10;
        enum to1=0x8201;
        auto dart1=new DART(net, from1, to1);
        assert(dart1.inRange(from1));
        assert(dart1.inRange(to1-0x100));
        assert(dart1.inRange(to1-1));
        assert(!dart1.inRange(to1));

        enum from2=0xFF80;
        enum to2=0x10;
        auto dart2=new DART(net, from2, to2);
        assert(!dart2.inRange(from2-1));
        assert(dart2.inRange(from2));
        assert(dart2.inRange(0));
        assert(dart2.inRange(to2-1));
        assert(!dart2.inRange(to2));
        assert(!dart2.inRange(42));
    }

}
