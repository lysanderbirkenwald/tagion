/// Recorder for the archives sread/removed and added to the DART 
module tagion.dart.Recorder;

import tagion.hibon.HiBONJSON;

version (REDBLACKTREE_SAFE_PROBLEM) {
    /// dmd v2.100+ has problem with rbtree
    /// Fix: This module hacks the @safe rbtree so it works with dmd v2.100 
    import tagion.std.container.rbtree : RedBlackTree;
}
else {
    import std.container.rbtree : RedBlackTree;
}
import std.range.primitives : isInputRange, ElementType;
import std.algorithm.iteration : map;
import std.format;
import std.range : empty;
import std.traits : FunctionTypeOf;
import std.functional : toDelegate;

import tagion.crypto.SecureInterfaceNet : HashNet;
import tagion.hibon.Document : Document;
import tagion.hibon.HiBON : HiBON;
import tagion.hibon.HiBONRecord : label, STUB, isHiBONRecord, GetLabel, isStub, recordType;
import tagion.basic.Types : Buffer;
import tagion.basic.Message;

import tagion.dart.DARTException : DARTRecorderException;
import tagion.dart.DARTBasic;

import tagion.basic.tagionexceptions : Check;

import tagion.utils.Miscellaneous : toHexString;
import tagion.basic.Version : ver;

import std.stdio : stdout, File;

alias hex = toHexString;

private alias check = Check!DARTRecorderException;

/**
 * Record factory
 * Used to construct and handle DART recorder
 */
@safe
class RecordFactory {
    enum order_remove_add = true;
    const HashNet net;
    @disable this();
    protected this(const HashNet net) {
        this.net = net;
    }

    static RecordFactory opCall(const HashNet net) {
        return new RecordFactory(net);
    }
    /**
     * Creates an empty Recorder
     * Returns:
     * new empty recorder
     */
    Recorder recorder() nothrow {
        return new Recorder;
    }

    /**
     * Creates an Recorder from a document
     * Params:
     *   doc = Documemt formated as recorder
     * Returns:
     *   new recorder created from doc
     */
    Recorder recorder(const(Document) doc) {
        return new Recorder(doc);
    }

    /**
     * Same as recorder but produce an immutable recorder
     * Params: doc
     */
    immutable(Recorder) uniqueRecorder(const(Document) doc) const @trusted {
        const result = new const(Recorder)(doc);
        return cast(immutable) result;
    }

    /**
     * This function should be use with care (rec should only be allocate once)
    * Params:
     * rec = is set to null after
     */
    immutable(Recorder) uniqueRecorder(ref Recorder rec) const pure nothrow @trusted {
        scope (exit) {
            rec = null;
        }
        return cast(immutable) rec;
    }

    /**
     * Creates a Recorder base on an existing archive list
     * Params:
     *     archives = Archive list
     */
    Recorder recorder(Recorder.Archives archives) nothrow {
        return new Recorder(archives);
    }

    Recorder recorder(R)(R range, const Archive.Type type = Archive.Type.NONE) if (isInputRange!R) {
        return new Recorder(range, type);
    }

    /**
     *  Recorder to recorder (REMOVE, ADD) actions while can be executed by the
     *  modify method
     */
    @safe
    @recordType("Recorder")
    class Recorder {
        /// This will order REMOVE before add

        alias archive_sorted = (a, b) @safe => (a.fingerprint < b.fingerprint) || (
                a.fingerprint == b.fingerprint) && (a._type < b._type);

        alias Archives = RedBlackTree!(Archive, archive_sorted);
        package Archives archives;

        import tagion.hibon.HiBONJSON : JSONString;

        mixin JSONString;
        import tagion.hibon.HiBONRecord : HiBONRecordType;

        mixin HiBONRecordType;
        /**
         * Creates a Recorder with an empty archive list
         * Params:
         *     net = Secure net should be the same as define in the DARTFile class
         */
        private this() pure nothrow {
            this.archives = new Archives;
        }

        /**
         * Creates an Recorder base on an existing archive list
         * Params:
         *     net      = Secure net should be the same as define in the DARTFile class
         *     archives = Archive list
         */
        private this(Archives archives) pure nothrow {
            this.archives = archives;
        }

        private this(R)(R range, const Archive.Type type = Archive.Type.NONE) if (isInputRange!R) {
            archives = new Archives;
            insert(range, type);
        }

        private this(Document doc) {

            

                .check(isRecord(doc), format("Document is not a %s", ThisType.stringof));
            this.archives = new Archives;
            foreach (e; doc[]) {
                if (e.key != TYPENAME) {
                    const doc_archive = e.get!Document;
                    auto archive = new Archive(net, doc_archive);
                    archives.insert(archive);
                }
            }
        }

        Recorder dup() pure nothrow {
            return new Recorder(archives.dup);
        }

        Archives.ConstRange opSlice() const pure nothrow {
            return archives[];
        }

        Archives.Range opSlice() pure nothrow {
            return archives[];
        }

        void removeOutOfRange(ushort from, ushort to) { //TODO: write unit tests
            if (from == to)
                return;
            immutable ushort to_origin = (to - from) & ushort.max;
            foreach (archive; archives) {
                if (archive.type != Archive.Type.REMOVE) {
                    short archiveSector = archive.fingerprint[0] | archive.fingerprint[1];
                    ushort sector_origin = (archiveSector - from) & ushort.max;
                    if (sector_origin >= to_origin) {
                        archives.removeKey(archive);
                    }
                }
            }
        }

        Recorder changeTypes(const GetType get_type) {
            import std.algorithm;

            auto result_archives = new Archives;
            result_archives.insert(
                    archives[].map!(a => new Archive(net, a.filed, get_type(a)))
            );
            return new Recorder(result_archives);
        }
        /** 
        * Length of the archives
        * Returns: number of archives 
        */
        size_t length() pure const nothrow {
            return archives.length;
        }

        /**
     * Check if the recorder contains archives
     * Returns:
     *   true if the recorder is empty
     */
        bool empty() pure const nothrow {
            return archives.length == 0;
        }

        /**
         * Finds an archive with the fingerprint
         *
         * Returns:
         *     The archive @ fingerprint and if it dosn't exists then a null reference is returned
         */
        Archive find(const(DARTIndex) fingerprint) {
            // in {
            //     assert(fingerprint);
            // }
            // do {
            if ((fingerprint.length !is 0) && (archives !is null)) {
                scope archive = new Archive(fingerprint, Archive.Type.NONE);
                scope range = archives.equalRange(archive);
                if ((!range.empty) && (archive.fingerprint == range.front.fingerprint)) {
                    return range.front;
                }
            }
            return null;
        }

        Archive find(const(Buffer) fingerprint) {
            return find(DARTIndex(fingerprint));
        }
        ///
        unittest { // Check find
            import tagion.crypto.SecureNet : StdHashNet;

            const hash_net = new StdHashNet;

            auto record_factory = RecordFactory(hash_net);
            Archive[DARTIndex] set_of_archives;
            foreach (i; 0 .. 7) {
                auto hibon = new HiBON;
                hibon["text"] = format("Some text %d", i);
                hibon["index"] = i;
                auto archive = new Archive(hash_net, Document(hibon));
                set_of_archives[archive.fingerprint] = archive;
            }

            auto recorder = record_factory.recorder;

            // Check for an empty record
            assert(recorder.find(set_of_archives.byKey.front) is null);

            // Fill up the record with set_of_archives
            foreach (a; set_of_archives) {
                recorder.insert(a);
            }

            foreach (a; set_of_archives) {
                auto archive_found = recorder.find(a.fingerprint);
                assert(archive_found);
                assert(archive_found is a);
            }

            { // None existing archive
                auto hibon = new HiBON;
                hibon["text"] = "Does not exist in the recoder";
                auto none_existing_archive = new Archive(hash_net, Document(hibon));
                assert(recorder.find(none_existing_archive.fingerprint) is null);
            }
        }
        /**
         * Clear all archives
         */
        void clear() {
            archives.clear;
        }

        final const(Archive) insert(const Document doc, const Archive.Type type = Archive.Type.NONE) {
            auto archive = new Archive(net, doc, type);
            archives.insert(archive);
            return archive;
        }

        final const(Archive) insert(T)(T pack, const Archive.Type type = Archive.Type.NONE)
                if ((isHiBONRecord!T) && !is(T : const(Recorder))) {
            return insert(pack.toDoc, type);
        }

        void insert(Archive archive) //, const Archive.Type type = Archive.Type.NONE)
        in (!archive.fingerprint.empty)
        do {
            archives.insert(archive);
        }

        const(Archive) add(T)(T pack) {
            return insert(pack, Archive.Type.ADD);
        }

        const(Archive) remove(T)(T pack) {
            return insert(pack, Archive.Type.REMOVE);
        }

        void insert(R)(R range, const Archive.Type type = Archive.Type.NONE) @trusted
                if ((isInputRange!R) && (is(ElementType!R : const(Document)) || isHiBONRecord!(
                    ElementType!R))) {
            alias FiledType = ElementType!R;
            static if (isHiBONRecord!FiledType) {
                archives.insert(range.map!(a => new Archive(net, a.toDoc, type)));
            }
            else {
                archives.insert(range.map!(a => new Archive(net, a, type)));
            }
        }

        final void insert(Recorder r) {
            archives.insert(r.archives[]);
        }

        final Archive archive(const Document doc, const Archive.Type type = Archive.Type.NONE) const {
            return new Archive(net, doc, type);
        }

        Archive archive(T)(T pack, const Archive.Type type = Archive.Type.NONE) const {
            return archive(pack.toDoc, type);
        }

        final void remove(const(DARTIndex) fingerprint)
        in {
            assert(fingerprint.length is net.hashSize,
                    format("Length of the fingerprint must be %d but is %d", net.hashSize, fingerprint
                    .length));
        }
        do {
            auto archive = new Archive(fingerprint, Archive.Type.REMOVE);
            archives.insert(archive);
        }

        final void remove(const(Buffer) fingerprint) {
            remove(DARTIndex(fingerprint));
        }

        final void stub(const(DARTIndex) fingerprint)
        in {
            assert(fingerprint.length is net.hashSize,
                    format("Length of the fingerprint must be %d but is %d", net.hashSize, fingerprint
                    .length));
        }
        do {
            auto archive = new Archive(fingerprint, Archive.Type.NONE);
            insert(archive);
        }

        final void stub(const(Buffer) fingerprint) {
            stub(DARTIndex(fingerprint));
        }

        void dump(File fout = stdout) const {

            foreach (a; archives) {
                a.dump(fout);
            }
        }

        final const(Document) toDoc() const {
            auto result = new HiBON;
            uint i;
            foreach (a; archives) {
                result[i] = a.toDoc;
                i++;
            }
            result[TYPENAME] = type_name;
            return Document(result);
        }

        import std.algorithm.sorting;

        bool checkSorted() pure {
            return opSlice
                .isSorted!(archive_sorted);
        }

    }
}

alias GetType = Archive.Type delegate(const(Archive)) pure @safe;

const Add = delegate(const(Archive) a) => Archive.Type.ADD;
const Remove = delegate(const(Archive) a) => Archive.Type.REMOVE;
const Flip = delegate(const(Archive) a) => -a.type;
const Neutral = delegate(const(Archive) a) => a.type;

/**
 * Archive element used in the DART Recorder
 */
@safe class Archive {
    enum Type : int {
        NONE = 0, /// NOP DART instruction
        REMOVE = -1, /// Archive marked as remove instruction
        ADD = 1, /// Archive marked as add instrunction
    }

    @label(STUB, true) const(DARTIndex) fingerprint; /// Stub hash-pointer used in sharding
    @label("$a", true) const Document filed; /// The actual data strute stored 
    enum archiveLabel = GetLabel!(this.filed).name;
    enum fingerprintLabel = GetLabel!(this.fingerprint).name;
    enum typeLabel = GetLabel!(this._type).name;
    private @label("$t", true) Type _type; /// Acrhive type
    protected @label("") bool _done; /// Marks if the operation was done on the archive

    mixin JSONString;
    /* 
    * Construct a
    * Params:
    *   net = hash function used 
    *   doc = document of an archive or filed doc
    *   t = archive type
    */
    this(const HashNet net, const(Document) doc, const Type t = Type.NONE)
    in {
        assert(net !is null);
        assert(!doc.empty, "Archive can not be empty");
    }
    do {
        if (.isStub(doc)) {
            fingerprint = net.dartIndex(doc);
        }
        else {
            if (doc.hasMember(archiveLabel)) {
                filed = doc[archiveLabel].get!Document;
            }
            else {
                filed = doc;
            }
            fingerprint = net.dartIndex(filed);
        }
        _type = t;
        if (_type is Type.NONE && doc.hasMember(typeLabel)) {
            _type = doc[typeLabel].get!Type;
        }

    }

    void dump(File fout = stdout) const {
        fout.writefln("Archive %s %s %s", fingerprint.hex, type,
                (() @trusted => cast(void*) this)());
    }

    override string toString() const {
        return format("Archive %s %s %s", fingerprint.hex, type,
                (() @trusted => cast(void*) this)());
    }
    /**
     * Construct an archive from a Document
     * Params:
     *   doc = documnet of the filed data
     *   t = archve type
     */
    version (none) this(const(Document) doc, const Type t = Type.NONE) {
        this(null, doc, t);
    }

    /**
     * Convert archive to a Document 
     * Returns: documnet of the archive
     */
    const(Document) toDoc() const {
        auto hibon = new HiBON;
        if (isStub) {
            hibon[fingerprintLabel] = fingerprint;
        }
        else {
            hibon[archiveLabel] = filed;
        }
        if (_type !is Type.NONE) {
            hibon[typeLabel] = _type;
        }
        return Document(hibon);
    }

    /** 
    * Define archive by it fingerprint
    * Use to read or remove an archive with a fingerprint
    * Params:
    *   fingerprint = hash-key to select the archive
    *   t = type must be either REMOVE or NONE 
    */
    private this(DARTIndex fingerprint, const Type t = Type.NONE)
    in (!fingerprint.empty)
    in (t !is Type.ADD)
    do {
        _type = t;
        filed = Document();
        this.fingerprint = fingerprint;
    }

    /**
     * Checks the translate function get_type result in a remove-type
     * Params:
     *   get_type = get-type translate function
     * Returns: true if acrhive is a remove type 
     *
     */
    final bool isRemove(GetType get_type) const {
        return get_type(this) is Type.REMOVE;
    }

    /**
     * Checks if the archive type is a remove-type 
     * Returns: true if type is REMOVE
     */
    final bool isRemove() pure const nothrow {
        return type is Type.REMOVE;
    }

    /** 
     * Checks if the archive is an add-type
     * Returns: true if type is ADD
     */
    final bool isAdd() pure const nothrow {
        return type is Type.ADD;
    }

    /**
     * Check if archive is a stub
     * Returns: true if archive is a stub
     */
    final bool isStub() pure const nothrow {
        return filed.empty;
    }

    /**
     * Check if the filed archive is of type T 
     * Returns: true if the archive is T
     */
    final bool isRecord(T)() const {
        return T.isRecord(filed);
    }

    final bool done() const pure nothrow @nogc {
        return _done;
    }

    /* 
     * Type of the archive
     * Returns: type 
     */
    final Type type() const pure nothrow @nogc {
        return _type;
    }

    /**
     * An Archive is only allowed to be done once
     */
    package final void doit() const pure nothrow @trusted
    in {
        assert(!_done, "An Archive can only be done once");
    }
    do {
        auto force_done = cast(bool*)(&_done);
        *force_done = true;
    }

    /**
     * Generates Document to be store in the BlockFile
     * Returns: the document to be stored
     */
    const(Document) store() const
    out (result) {
        assert(!result.empty, format("Archive is %s type and it must contain data", type));
    }
    do {
        if (filed.empty) {
            auto hibon = new HiBON;
            hibon[fingerprintLabel] = fingerprint;
            return Document(hibon);
        }
        return filed;
    }

}

///
unittest { // Archive
    //    import std.stdio;
    import std.format;
    import tagion.hibon.HiBONJSON;
    import tagion.dart.DARTFakeNet;
    import tagion.utils.Miscellaneous : toHex = toHexString;
    import std.string : representation;

    auto net = new DARTFakeNet;
    auto manufactor = RecordFactory(net);

    static assert(isHiBONRecord!Archive);
    Document filed_doc; // This is the data which is filed in the DART
    {
        auto hibon = new HiBON;
        hibon["text"] = "Some text";
        filed_doc = Document(hibon);
    }
    immutable filed_doc_fingerprint = net.dartIndex(filed_doc);

    Archive a;
    { // Simple archive
        a = new Archive(net, filed_doc);
        assert(!a.isStub);
        assert(a.fingerprint == filed_doc_fingerprint);
        assert(a.filed == filed_doc);
        assert(a.type is Archive.Type.NONE);

        const archived_doc = a.toDoc;
        assert(archived_doc[Archive.archiveLabel].get!Document == filed_doc);
        const result_a = new Archive(net, archived_doc);
        assert(result_a.fingerprint == a.fingerprint);
        assert(result_a.filed == a.filed);
        assert(result_a.type == a.type);
        assert(!result_a.isStub);
        assert(result_a.store == filed_doc);

    }

    a._type = Archive.Type.ADD;
    { // Simple archive with ADD/REMOVE Type
        // a=new Archive(net, filed_doc);
        assert(!a.isStub);
        assert(a.fingerprint == filed_doc_fingerprint);
        const archived_doc = a.toDoc;

        { // Same type
            const result_a = new Archive(net, archived_doc);
            assert(result_a.fingerprint == a.fingerprint);
            assert(result_a.filed == a.filed);
            assert(result_a.type == a.type);
            assert(!result_a.isStub);
            assert(result_a.store == filed_doc);
        }

    }

    { // Filed archive with hash-key
        enum key_name = "#name";
        enum keytext = "some_key_text";
        immutable hashkey_fingerprint = net.calcHash(keytext.representation);
        Document filed_hash;
        {
            auto hibon = new HiBON;
            hibon[key_name] = keytext;
            filed_hash = Document(hibon);
        }
        auto hash = new Archive(net, filed_hash, Archive.Type.NONE);
        assert(hash.fingerprint == hashkey_fingerprint);
    }

}

unittest { /// RecordFactory.Recorder.insert range
    import tagion.hibon.HiBONRecord;
    import tagion.crypto.SecureNet;
    import std.range : iota, chain;
    import std.algorithm.sorting : sort;
    import std.algorithm.comparison : equal;
    import std.array : array;

    import std.stdio : writefln;

    const net = new StdHashNet;
    auto manufactor = RecordFactory(net);
    static struct Filed {
        int x;
        mixin HiBONRecord!(
                q{
                this(int x) {
                    this.x = x;
                }
            });
    }

    auto range_filed = iota(5).map!(i => Filed(i));

    auto recorder = manufactor.recorder(range_filed);

    enum recorder_sorted = (RecordFactory.Recorder rec) @safe => rec[]
            .map!(a => Filed(a.filed))
            .array
            .sort!((a, b) => a.x < b.x);

    { // Check the content of
        assert(equal(range_filed, recorder_sorted(recorder)));
    }

    { // Insert range of HiBON's
        auto range_filed_insert = iota(5, 10).map!(i => Filed(i));
        recorder.insert(range_filed_insert);
        assert(equal(
                chain(range_filed, range_filed_insert),
                recorder_sorted(recorder)));
    }

    { /// Insert recorder to recorder

        auto recorder_base = manufactor.recorder(iota(3, 6).map!(i => Filed(i)));
        auto recorder_insert = manufactor.recorder(iota(0, 3).map!(i => Filed(i)));
        recorder_base.insert(recorder_insert);
        assert(equal(
                recorder_sorted(recorder_base),
                iota(0, 6).map!(i => Filed(i))));
    }

}

@safe
unittest {
    immutable(ulong[]) table = [
        //  RIM 2 test (rim=2)
        0x20_21_10_30_40_50_80_90,
        0x20_21_11_30_40_50_80_90,
        0x20_21_12_30_40_50_80_90,
        0x20_21_0a_30_40_50_80_90, // Insert before in rim 2

    ];

    import std.array : array;
    import tagion.dart.DARTFakeNet;

    const net = new DARTFakeNet;
    auto manufactor = RecordFactory(net);
    { /// Remove must come before two archive with the same fingerprint

        const doc = DARTFakeNet.fake_doc(0x1234_5678_0000_0000);
        auto rec = manufactor.recorder;
        rec.insert(doc, Archive.Type.ADD);
        rec.insert(doc, Archive.Type.REMOVE);

        import std.stdio;

        writeln(" ------------------------------ ");
        //rec.dump;

        const archs = table.map!(t => DARTFakeNet.fake_doc(t)).array;

        rec.insert(archs[0], Archive.Type.ADD);
        rec.insert(archs[1], Archive.Type.REMOVE);
        rec.insert(archs[3], Archive.Type.ADD);
        rec.insert(archs[1], Archive.Type.ADD);
        rec.insert(archs[1], Archive.Type.ADD);
        rec.insert(archs[3], Archive.Type.REMOVE);
        rec.insert(archs[2], Archive.Type.ADD);

        //rec.//dump;
        assert(rec.checkSorted);

    }
}
