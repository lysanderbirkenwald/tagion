module tagion.crypto.SecureNet;

import tagion.crypto.SecureInterfaceNet;
import tagion.crypto.aes.AESCrypto;
import tagion.basic.Basic: Buffer, Signature;
import tagion.hibon.Document: Document;
import tagion.hibon.HiBONRecord: HiBONPrefix, STUB;
import tagion.basic.ConsensusExceptions;

void scramble(scope ref ubyte[] data, scope ubyte[] xor = null) @safe {
    import std.random;

    auto gen = Mt19937(unpredictableSeed);
    foreach (ref s; data) { //, gen1, StoppingPolicy.shortest)) {
        s = gen.front & ubyte.max;
        gen.popFront;
    }
    foreach (i, x; xor) {
        data[i] ^= x;
    }
}

private alias check = Check!SecurityConsensusException;

@safe
class StdHashNet : HashNet {
    import std.format;

    //    import std.stdio;
    protected enum HASH_SIZE = 32;
    @nogc final uint hashSize() const pure nothrow {
        return HASH_SIZE;
    }

    final immutable(Buffer) rawCalcHash(scope const(ubyte[]) data) const {
        import std.digest.sha: SHA256;
        import std.digest;

        return digest!SHA256(data).idup;
    }

    immutable(Buffer) calcHash(scope const(ubyte[]) data) const {
        version (unittest) {
            assert(!Document(data.idup).isInorder, "calcHash should not be use on a Document use hashOf instead");
        }
        return rawCalcHash(data);
    }

    @trusted
    final immutable(Buffer) HMAC(scope const(ubyte[]) data) const pure {
        import std.exception: assumeUnique;
        import std.digest.sha: SHA256;
        import std.digest.hmac: digestHMAC = HMAC;

        scope hmac = digestHMAC!SHA256(data);
        auto result = hmac.finish.dup;
        return assumeUnique(result);
    }

    immutable(Buffer) calcHash(scope const(ubyte[]) h1, scope const(ubyte[]) h2) const
    in {
        assert(h1.length is 0 || h1.length is HASH_SIZE,
                format("h1 is not a valid hash (length=%d should be 0 or %d", h1.length, HASH_SIZE));
        assert(h2.length is 0 || h2.length is HASH_SIZE,
                format("h2 is not a valid hash (length=%d should be 0 or %d", h2.length, HASH_SIZE));
    }
    out (result) {
        if (h1.length is 0) {
            assert(h2 == result);
        }
        else if (h2.length is 0) {
            assert(h1 == result);
        }
    }
    do {
        pragma(msg, "dlang: Pre and post condition does not work here");
        assert(h1.length is 0 || h1.length is HASH_SIZE,
                format("h1 is not a valid hash (length=%d should be 0 or %d", h1.length, HASH_SIZE));
        assert(h2.length is 0 || h2.length is HASH_SIZE,
                format("h2 is not a valid hash (length=%d should be 0 or %d", h2.length, HASH_SIZE));
        if (h1.length is 0) {
            return h2.idup;
        }
        if (h2.length is 0) {
            return h1.idup;
        }
        return rawCalcHash(h1 ~ h2);
    }

    immutable(Buffer) hashOf(const(Document) doc) const {
        if (!doc.empty && (doc.keys.front[0] is HiBONPrefix.HASH)) {
            if (doc.keys.front == STUB) {
                return doc[STUB].get!Buffer;
            }
            auto first = doc[].front;
            immutable value_data = first.data[first.dataPos .. first.dataPos + first.dataSize];
            return rawCalcHash(value_data);
        }
        return rawCalcHash(doc.serialize);
    }
}

@safe
class StdSecureNet : StdHashNet, SecureNet {
    import tagion.crypto.secp256k1.NativeSecp256k1;
    import tagion.basic.Basic: Pubkey;
    import tagion.crypto.aes.AESCrypto;

    //    import tagion.gossip.GossipNet : scramble;
    import tagion.basic.ConsensusExceptions;

    import std.format;
    import std.string: representation;

    private Pubkey _pubkey;
    /**
       This function
       returns
       If method is SIGN the signed message or
       If method is DERIVE it returns the derived privat key
    */
    @safe
    interface SecretMethods {
        immutable(ubyte[]) sign(const(ubyte[]) message) const;
        void tweakMul(const(ubyte[]) tweek_code, ref ubyte[] tweak_privkey);
        void tweakAdd(const(ubyte[]) tweek_code, ref ubyte[] tweak_privkey);
        immutable(ubyte[]) ECDHSecret(const(Pubkey) pubkey) const;
        Buffer mask(const(ubyte[]) _mask) const;
    }

    protected SecretMethods _secret;

    @nogc final Pubkey pubkey() pure const nothrow {
        return _pubkey;
    }

    final Buffer hmacPubkey() const {
        return HMAC(cast(Buffer) _pubkey);
    }

    final Pubkey derivePubkey(string tweak_word) const {
        const tweak_code = HMAC(tweak_word.representation);
        return derivePubkey(tweak_code);
    }

    final Pubkey derivePubkey(const(ubyte[]) tweak_code) const {
        Pubkey result;
        const pkey = cast(const(ubyte[])) _pubkey;
        result = _crypt.pubKeyTweakMul(pkey, tweak_code);
        return result;
    }

    protected NativeSecp256k1 _crypt;

    bool verify(const(ubyte[]) message, const Signature signature, const Pubkey pubkey) const {
        consensusCheck!(SecurityConsensusException)(signature.length != 0 && signature.length <= 520,
                ConsensusFailCode.SECURITY_SIGNATURE_SIZE_FAULT);
        return _crypt.verify(message, cast(Buffer) signature, cast(Buffer) pubkey);
    }

    Signature sign(const(ubyte[]) message) const
    in {
        assert(_secret !is null, format("Signature function has not been intialized. Use the %s function", basename!generatePrivKey));
        assert(message.length == 32);
    }
    do {
        import std.traits;

        assert(_secret !is null, format("Signature function has not been intialized. Use the %s function", fullyQualifiedName!generateKeyPair));

        return Signature(_secret.sign(message));
    }

    final void derive(string tweak_word, ref ubyte[] tweak_privkey) {
        const data = HMAC(tweak_word.representation);
        derive(data, tweak_privkey);
    }

    final void derive(const(ubyte[]) tweak_code, ref ubyte[] tweak_privkey)
    in {
        assert(tweak_privkey.length >= 32);
    }
    do {
        _secret.tweakMul(tweak_code, tweak_privkey);
    }

    final Buffer mask(const(ubyte[]) _mask) const {
        return _secret.mask(_mask);
    }

    @trusted
    void derive(string tweak_word, shared(SecureNet) secure_net) {
        const tweak_code = HMAC(tweak_word.representation);
        derive(tweak_code, secure_net);
    }

    @trusted
    void derive(const(ubyte[]) tweak_code, shared(SecureNet) secure_net)
    in {
        assert(_secret);
    }
    do {
        synchronized (secure_net) {
            ubyte[] tweak_privkey = tweak_code.dup;
            auto unshared_secure_net = cast(SecureNet) secure_net;
            unshared_secure_net.derive(tweak_code, tweak_privkey);
            createKeyPair(tweak_privkey);
        }
    }

    final void createKeyPair(ref ubyte[] privkey)
    in {
        assert(_crypt.secKeyVerify(privkey));
        assert(_secret is null);
    }
    do {
        import std.digest.sha: SHA256;
        import std.string: representation;

        alias AES = AESCrypto!256;
        _pubkey = _crypt.computePubkey(privkey);
        // Generate scramble key for the private key
        import std.random;

        auto seed = new ubyte[32];

        scramble(seed);
        // CBR: Note AES need to be change to beable to handle const keys
        import std.stdio;
        writefln("Document(seed.idup).isInorder %s", Document(seed.idup).isInorder);
        auto aes_key = rawCalcHash(seed).dup;
        //        ubyte[AES.BLOCK_SIZE] aes_iv;
        scramble(seed);
        auto aes_iv = rawCalcHash(seed)[4 .. 4 + AES.BLOCK_SIZE].dup;

        // Encrypt private key
        auto encrypted_privkey = new ubyte[privkey.length];
        AES.encrypt(aes_key, aes_iv, privkey, encrypted_privkey);

        AES.encrypt(calcHash(seed), aes_iv, encrypted_privkey, privkey);
        scramble(seed);

        AES.encrypt(aes_key, aes_iv, encrypted_privkey, privkey);

        AES.encrypt(aes_key, aes_iv, privkey, seed);

        AES.encrypt(aes_key, aes_iv, encrypted_privkey, privkey);

        @safe
        void do_secret_stuff(scope void delegate(const(ubyte[]) privkey) @safe dg) {
            // CBR:
            // Yes I know it is security by obscurity
            // But just don't want to have the private in clear text in memory
            // for long period of time
            auto privkey = new ubyte[encrypted_privkey.length];
            scope (exit) {
                auto seed = new ubyte[32];
                scramble(seed, aes_key);
                scramble(aes_key, seed);
                scramble(aes_iv);
                AES.encrypt(aes_key, aes_iv, privkey, encrypted_privkey);
                AES.encrypt(calcHash(seed), aes_iv, encrypted_privkey, privkey);
            }
            AES.decrypt(aes_key, aes_iv, encrypted_privkey, privkey);
            dg(privkey);
        }

        @safe class LocalSecret : SecretMethods {
            immutable(ubyte[]) sign(const(ubyte[]) message) const {
                immutable(ubyte)[] result;
                do_secret_stuff((const(ubyte[]) privkey) {
                    result = _crypt.sign(message, privkey);
                });
                return result;
            }

            void tweakMul(const(ubyte[]) tweak_code, ref ubyte[] tweak_privkey) {
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    _crypt.privKeyTweakMul(privkey, tweak_code, tweak_privkey);
                });
            }

            void tweakAdd(const(ubyte[]) tweak_code, ref ubyte[] tweak_privkey) {
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    _crypt.privKeyTweakAdd(privkey, tweak_code, tweak_privkey);
                });
            }

            immutable(ubyte[]) ECDHSecret(const(Pubkey) pubkey) const {
                Buffer result;
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                        result = _crypt.createECDHSecret(privkey, cast(Buffer)pubkey);
                });
                return result;
            }

            Buffer mask(const(ubyte[]) _mask) const {
                import std.algorithm.iteration: sum;

                check(sum(_mask) != 0, ConsensusFailCode.SECURITY_MASK_VECTOR_IS_ZERO);
                Buffer result;
                do_secret_stuff((const(ubyte[]) privkey) @safe {
                    import tagion.utils.Miscellaneous: xor;

                    auto data = xor(privkey, _mask);
                    result = calcHash(calcHash(data));
                });
                return result;
            }
        }

        _secret = new LocalSecret;
    }

    final void generateKeyPair(string passphrase)
    in {
        assert(_secret is null);
    }
    do {
        import std.digest.sha: SHA256;
        import std.digest.hmac: digestHMAC = HMAC;
        import std.string: representation;

        alias AES = AESCrypto!256;

        scope hmac = digestHMAC!SHA256(passphrase.representation);
        auto data = hmac.finish.dup;

        // Generate Key pair
        do {
            data = hmac.put(data).finish.dup;
        }
        while (!_crypt.secKeyVerify(data));

        createKeyPair(data);
    }

    immutable(ubyte[]) ECDHSecret(const(ubyte[]) seckey, const(
            Pubkey) pubkey) const {
        return _crypt.createECDHSecret(seckey, cast(Buffer)pubkey);
    }

    immutable(ubyte[]) ECDHSecret(const(Pubkey) pubkey) const {
        return _secret.ECDHSecret(pubkey);
    }

    Pubkey computePubkey(const(ubyte[]) seckey, immutable bool compress = true) const {
        return Pubkey(_crypt.computePubkey(seckey, compress));
    }

    this() {
        this._crypt = new NativeSecp256k1;
    }

    unittest { // StdSecureNet
        import std.stdio;
        import tagion.hibon.HiBONJSON;

        import tagion.hibon.HiBON;
        import std.exception: assertThrown;
        import tagion.basic.ConsensusExceptions: SecurityConsensusException;

        SecureNet net = new StdSecureNet;
        net.generateKeyPair("Secret password");

        Document doc;
        {
            auto h = new HiBON;
            h["message"] = "Some message";
            doc = Document(h);
        }

        writefln("doc %s", doc.toJSON);
        const doc_signed = net.sign(doc);

        assert(doc_signed.message == net.rawCalcHash(doc.serialize));
        assert(net.verify(doc, doc_signed.signature, net.pubkey));

        { // Hash key
            auto h = new HiBON;
            h["#message"] = "Some message";
            doc = Document(h);
        }

        // A document containing a hash-ket can not be signed or verified
        assertThrown!SecurityConsensusException(net.sign(doc));
        assertThrown!SecurityConsensusException(net.verify(doc, doc_signed.signature, net.pubkey));

    }

}

unittest { // StdHashNet
    //import tagion.utils.Miscellaneous : toHex=toHexString;
    import tagion.hibon.HiBONRecord: isStub, hasHashKey;
    import std.string: representation;
    import std.exception: assertThrown;
    import core.exception: AssertError;

    // import std.stdio;

    import tagion.hibon.HiBON;

    const net = new StdHashNet;
    Document doc; // This is the data which is filed in the DART
    {
        auto hibon = new HiBON;
        hibon["text"] = "Some text";
        doc = Document(hibon);
    }

    immutable doc_fingerprint = net.rawCalcHash(doc.serialize);

    { // calcHash should not be used on a Document hashOf should be used instead
        assertThrown!AssertError(net.calcHash(doc.serialize));

        assertThrown!AssertError(net.calcHash(doc.serialize, null));
        assertThrown!AssertError(net.calcHash(null, doc.serialize));
    }

    {
        assert(net.calcHash(null, null).length is 0);
        assert(net.calcHash(doc_fingerprint, null) == doc_fingerprint);
        assert(net.calcHash(null, doc_fingerprint) == doc_fingerprint);
    }

    immutable stub_fingerprint = net.calcHash(doc_fingerprint, doc_fingerprint);
    Document stub;
    {
        auto hibon = new HiBON;
        hibon[STUB] = stub_fingerprint;
        stub = Document(hibon);
    }

    { // calcHash should not be used on a Document hashOf should be used instead
        assertThrown!AssertError(net.calcHash(stub.serialize));
    }

    assert(isStub(stub));
    assert(!hasHashKey(stub));

    assert(net.hashOf(stub) == stub_fingerprint);

    enum key_name = "#name";
    enum keytext = "some_key_text";
    immutable hashkey_fingerprint = net.calcHash(keytext.representation);
    Document hash_doc;
    {
        auto hibon = new HiBON;
        hibon[key_name] = keytext;
        hash_doc = Document(hibon);
    }

    assert(!isStub(hash_doc));
    assert(hasHashKey(hash_doc));
    assert(net.hashOf(hash_doc) == hashkey_fingerprint);
}

class BadSecureNet : StdSecureNet {
    this(string passphrase) {
        super();
        generateKeyPair(passphrase);
    }

    override Signature sign(const(ubyte[]) message) const {
        immutable false_message = super.rawCalcHash(message ~ message);
        return super.sign(false_message);
    }
}
