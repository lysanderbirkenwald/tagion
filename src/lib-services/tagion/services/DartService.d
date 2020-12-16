module tagion.services.DartService;

import core.thread;
import std.concurrency;

import p2plib = p2p.node;
import p2p.connection;
import p2p.callback;
import p2p.cgo.helper;

import tagion.basic.Logger;
import tagion.basic.Basic : Buffer, Control;
import tagion.basic.TagionExceptions;

import std.getopt;
import std.stdio;
import std.conv;
import tagion.utils.Miscellaneous : toHexString, cutHex;
import tagion.dart.DARTFile;
import tagion.dart.DART;
version(unittest) {
    import tagion.dart.BlockFile : fileId;
}
import tagion.basic.Basic;
import tagion.Keywords;
import tagion.crypto.secp256k1.NativeSecp256k1;
import tagion.dart.DARTSynchronization;
import tagion.Options;
import tagion.hibon.HiBONJSON;
import tagion.hibon.Document;
import tagion.hibon.HiBON : HiBON;
import tagion.communication.HandlerPool;

import tagion.communication.HiRPC;
import tagion.services.DartSynchronizeService;
import tagion.gossip.InterfaceNet: SecureNet;
//import tagion.services.MdnsDiscoveryService;
import tagion.gossip.P2pGossipNet : NodeAddress;

import std.array;

alias HiRPCSender = HiRPC.HiRPCSender;
alias HiRPCReceiver = HiRPC.HiRPCReceiver;

void dartServiceTask(Net : SecureNet)(immutable(Options) opts, shared(p2plib.Node) node, shared(Net) master_net, immutable(DART.SectorRange) sector_range) nothrow {
    try{
        setOptions(opts);
        immutable task_name=opts.dart.task_name;
        auto pid = opts.dart.protocol_id;
        log.register(task_name);

        log("-----Start Dart service-----");
        scope(success){
            log("------Stop Dart service-----");
            ownerTid.prioritySend(Control.END);
        }

        scope(failure){
            log.fatal("------Error Stop Dart service-----");
            ownerTid.prioritySend(Control.END);
        }

        bool stop = false;
        void handleControl (Control ts) {
            with(Control) switch(ts) {
                case STOP:
                    log("Kill dart service");
                    stop = true;
                    break;
                default:
                    log.error("Bad Control command %s", ts);
                }
        }
        const is_active_node = (!opts.dart.master_from_port) || opts.port == opts.dart.subs.master_port;
        Tid subscribe_handler_tid;
        if(is_active_node){
            log("Handling for subscription");
            node.listen(
                opts.dart.subs.protocol_id,
                &StdHandlerCallback,
                opts.dart.subs.master_task_name,
                opts.dart.subs.host.timeout.msecs,
                cast(uint) opts.dart.subs.host.max_size
            );
            subscribe_handler_tid = spawn(&subscibeHandler, opts);
        }
        scope(exit){
            if(is_active_node){
                node.closeListener(opts.dart.subs.protocol_id);
                send(subscribe_handler_tid, Control.STOP);
                receiveOnly!Control;
            }
        }

        node.listen(
            pid,
            &StdHandlerCallback,
            task_name,
            opts.dart.host.timeout.msecs,
            cast(uint) opts.dart.host.max_size
        );
        scope(exit){
            node.closeListener(pid);
        }

        auto connectionPool = new shared(ConnectionPool!(shared p2plib.Stream, ulong))(opts.dart.host.timeout.msecs);

        auto dart_sync_tid = locate(opts.dart.sync.task_name);

        auto net = new Net();
        net.drive(opts.dart.task_name, master_net);

        HiRPC hirpc;
        auto empty_hirpc = HiRPC(null);
        hirpc.net = net;

        auto requestPool = new StdHandlerPool!(ResponseHandler, uint)(opts.dart.commands.read_timeout.msecs);

        NodeAddress[string] node_addrses;

        enum recorder_hrpc_id = 1;
        log("sending live");
        ownerTid.send(Control.LIVE);
        while(!stop) {
            pragma(msg, "fixme(alex): 1000.msecs shoud be an option");
            receiveTimeout(
                    1000.msecs,
                    &handleControl,
                    (Response!(ControlCode.Control_Connected) resp) {
                        log("DS: Client Connected key: %d", resp.key);
                        connectionPool.add(resp.key, resp.stream, true);
                    },
                    (Response!(ControlCode.Control_Disconnected) resp) {
                        log("DS: Client Disconnected key: %d", resp.key);
                        connectionPool.close(cast(void*)resp.key);
                    },
                    (Response!(ControlCode.Control_RequestHandled) resp) {
                        log("DS: response received");

                        scope(exit){
                            if(resp.stream !is null){
                                destroy(resp.stream);
                            }
                        }
                        auto doc = Document(resp.data);
                        auto message_doc = doc[Keywords.message].get!Document;
                        void closeConnection(){
                            log("DSS: Forced close connection");
                            connectionPool.close(resp.key);
                        }

                        auto response = ResponseHandler.Response!uint(message_doc[Keywords.id].get!uint, resp.data);
                        requestPool.setResponse(response);

                    },
                    (immutable(DARTFile.Recorder) recorder){ //TODO: change to HiRPC
                        log("DS: received recorder");
                        if(subscribe_handler_tid !=Tid.init){
                            send(subscribe_handler_tid, recorder);
                        }
                        auto params=new HiBON;
                        params[DARTFile.Params.recorder]=recorder.toHiBON;
                        auto request = empty_hirpc.dartModify(params, recorder_hrpc_id); //TODO: remove out of range archives
                        auto request_data = cast(Buffer) empty_hirpc.toHiBON(request).serialize;
                        auto dstid = locate(opts.dart.sync.task_name);
                        if(dstid != Tid.init){
                            send(dstid, task_name, request_data); //TODO: => handle for the bullseye from dart
                        }
                        else{
                            log("Cannot locate Dart synchronize service");
                        }
                    },
                    (Buffer data, bool flag){
                        auto doc = Document(data);
                        auto message_doc = doc[Keywords.message].get!Document;
                        const hirpc_id = message_doc[Keywords.id].get!uint;
                        if(hirpc_id != recorder_hrpc_id){
                            auto response = ResponseHandler.Response!uint(hirpc_id, data);
                            requestPool.setResponse(response);
                        }
                        else{
                            auto result_doc = message_doc[Keywords.result].get!Document;
                            auto bullseye = result_doc[DARTFile.Params.bullseye].get!Buffer;
                            log(bullseye.cutHex);
                        }
                    },
                    (string taskName, Buffer data){
                        log("DS: Received request from service: %s", taskName);
                        const doc = Document(data);
                        auto receiver = empty_hirpc.receive(doc);
                        const message_doc = doc[Keywords.message].get!Document;
                        const hrpc_id = message_doc[Keywords.id].get!uint;

                        const method = message_doc[Keywords.method].get!string;

                        void readDart(){
                            scope doc_fingerprints=receiver.params[DARTFile.Params.fingerprints].get!(Document);
                            scope fingerprints=doc_fingerprints.range!(Buffer[]);
                            alias bufArr = Buffer[];
                            bufArr[NodeAddress] remote_fp_requests;
                            Buffer[] local_fp;
                            fpIterator: foreach(fp; fingerprints){
                                ushort sector = fp[0] | fp[1];
                                if(sector_range.inRange(sector)){
                                    local_fp~=fp;
                                    continue fpIterator;
                                }
                                else{
                                    foreach(address, fps; remote_fp_requests){
                                        if(address.sector.inRange(sector)){
                                            fps~=fp;
                                            remote_fp_requests[address] = fps;
                                            continue fpIterator;
                                        }
                                    }
                                    foreach(id, address; node_addrses){
                                        if(address.sector.inRange(sector)){
                                            remote_fp_requests[address] = [fp];
                                            continue fpIterator;
                                        }
                                    }
                                }
                                throw new TagionException("No address for fp");
                            }
                            // auto recorder=dart.loads(local_fp, DARTFile.Recorder.Archive.Type.ADD);
                            auto rs = cast(ResponseHandler)(new ReadRequestHandler(array(fingerprints), hirpc, taskName, receiver));
                            // if(local_fp.length>0){
                            //     requestPool.setResponse(ResponseHandler.Response!uint(hrpc_id, empty_hirpc.result(receiver, recorder.toHiBON).toHiBON(net).serialize));
                            // }
                            requestPool.add(hrpc_id, rs);
                            Buffer requestData(HiRPC hirpc, bufArr fps) {
                                auto params=new HiBON;
                                auto params_fingerprints=new HiBON;
                                foreach(i, b; fps) {
                                    if ( b.length !is 0 ) {
                                        params_fingerprints[i]=b;
                                    }
                                }
                                params[DARTFile.Params.fingerprints]=params_fingerprints;
                                const request = hirpc.dartRead(params, hrpc_id);
                                return hirpc.toHiBON(request).serialize;
                            }

                            if(remote_fp_requests.length > 0){
                                import std.array;
                                foreach(addr, fps; remote_fp_requests){
                                    auto stream = node.connect(addr.address, addr.is_marshal, [opts.dart.sync.protocol_id]);
                                    // connectionPool.add(stream.Identifier, stream);
                                    stream.listen(&StdHandlerCallback, task_name, opts.dart.sync.host.timeout.msecs, opts.dart.sync.host.max_size);
                                    immutable foreign_data = requestData(hirpc, fps);
                                    stream.writeBytes(foreign_data);
                                }
                            }
                            if(local_fp.length>0){
                                immutable foreign_data = requestData(empty_hirpc, local_fp);
                                send(dart_sync_tid, opts.dart.task_name, foreign_data);
                            }
                        }

                        void modifyDart(){  //TODO: not implemented yet
                            HiRPC.check_element!Document(receiver.params, DARTFile.Params.recorder);
                            auto mrh = cast(ResponseHandler)(new ModifyRequestHandler(hirpc, taskName, receiver));
                            requestPool.add(hrpc_id, mrh);
                            send(dart_sync_tid, data);
                        }

                        if(method == DART.Quries.dartRead){
                            readDart();
                        }
                        else if(method == DART.Quries.dartModify){
                            modifyDart();
                        }
                    },
                    (NodeAddress[string] update){
                        node_addrses = update;
                    },
                    // (immutable(TagionException) e) {
                    //     stop=true;
                    //     ownerTid.send(e);
                    // },
                    (immutable(TaskFailure) t) {
                        stop=true;
                        ownerTid.send(t);
                    },
                    // (immutable(Exception) e) {
                    //     //log.fatal(e.msg);
                    //     stop=true;
                    //     ownerTid.send(e);
                    // },
                    // (immutable(Throwable) t) {
                    //     //log.fatal(t.msg);
                    //     stop=true;
                    //     ownerTid.send(t);
                    // }
                );
            requestPool.tick();
        }
    }
    catch(Throwable e){
        fatal(e);
        // immutable task_e = e.taskException;
        // log(task_e);
        // ownerTid.send(task_e);
        // writefln("EXCEPTION: %s", e);
        // pragma(msg, "fixme(alex): Why doesn't this send the exception to the owner");
    }
}

private void subscibeHandler(immutable(Options) opts){
    log.register(opts.dart.subs.master_task_name);
    auto connectionPool = new shared(ConnectionPool!(shared p2plib.Stream, ulong))(opts.dart.subs.host.timeout.msecs);
    bool stop = false;

    void handleControl (Control ts) {
        with(Control) switch(ts) {
            case STOP:
                log("Kill dart service");
                stop = true;
                break;
            default:
                log.error("Bad Control command %s", ts);
            }
    }
    do{
        pragma(msg, "fixme(alex): 1000.msecs shoud be an option");
        receiveTimeout(
                    1000.msecs,
                    &handleControl,
                    (Response!(ControlCode.Control_Connected) resp) {
                        log("DS-subs: Client Connected key: %d", resp.key);
                        connectionPool.add(resp.key, resp.stream, true);
                    },
                    (Response!(ControlCode.Control_Disconnected) resp) {
                        log("DS-subs: Client Disconnected key: %d", resp.key);
                        connectionPool.close(resp.key);
                    },
                    (immutable(DARTFile.Recorder) recorder){ //TODO: change to HiRPC
                        log("DS-subs: received recorder");
                        connectionPool.broadcast(recorder.toHiBON.serialize); //+save to journal etc..
                        // if not ready/started => send error
                        // if(dartSyncTid != Tid.init){
                        //     send(dartSyncTid, recorder);
                        // }
                    },
        );
        connectionPool.tick();
    } while(!stop);
}
