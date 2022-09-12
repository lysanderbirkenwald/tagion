module tagion.script.NameCardScripts;

import std.typecons;

import tagion.dart.DART;
import tagion.dart.DARTFile;
import tagion.basic.Types : Buffer, FileExtension;

import tagion.communication.HiRPC;
import tagion.gossip.AddressBook;
import tagion.crypto.SecureInterfaceNet : HashNet;
import tagion.hibon.Document;
import tagion.hibon.HiBONRecord;
import tagion.hibon.HiBONJSON;

import tagion.dart.Recorder;
import tagion.script.StandardRecords;

import tagion.basic.Basic : doFront;

Nullable!T readStandardRecord(T)(
    const(HashNet) net,
    HiRPC hirpc,
    DART db,
    Buffer hash,
) if (isHiBONRecord!T)
{

    const(Document) readDocFromDB(Buffer[] fingerprints, HiRPC hirpc, DART db)
    {
        const sender = DART.dartRead(fingerprints, hirpc);
        auto receiver = hirpc.receive(sender.toDoc);
        return db(receiver, false).message["result"].get!Document;
    }

    Nullable!T fromArchive(T)(const(Archive) archive) if (isHiBONRecord!T)
    {
        if (archive is Archive.init)
        {
            return Nullable!T.init;
        }
        else
        {
            return Nullable!T(T(archive.filed));
        }
    }

    auto factory = RecordFactory(net);

    return fromArchive!T(
        factory.recorder(readDocFromDB([hash], hirpc, db))[].doFront
    );
}
