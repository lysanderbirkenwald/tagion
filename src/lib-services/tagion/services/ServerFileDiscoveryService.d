module tagion.services.ServerFileDiscoveryService;

import core.time;
import std.datetime;
import tagion.Options;
import std.typecons;
import std.conv;
import tagion.services.LoggerService;
import std.concurrency;
import tagion.basic.Basic : Buffer, Control, nameOf, Pubkey;
import std.stdio;
import tagion.services.MdnsDiscoveryService;

import tagion.hibon.HiBON : HiBON;
import tagion.hibon.Document : Document;
import std.file;
import std.file: fwrite = write;
import std.array;
import p2plib = p2p.node;
import std.net.curl;
import tagion.hibon.HiBONJSON;

enum ServerRequestCommand{
    BecomeOnline = 1,
    RequestTable = 2,
    BecomeOffline =3,
}

void serverFileDiscoveryService(Pubkey pubkey, shared p2plib.Node node, immutable(Options) opts){  //TODO: for test
    try{
        scope(exit){
            log("exit");
            ownerTid.prioritySend(Control.END);
        }

        log.register(opts.discovery.task_name);

        if(opts.serverFileDiscovery.url.length == 0){
            log.error("Server url is missing");
            ownerTid.send(Control.STOP);
            return;
        }

        bool checkTimestamp(SysTime time, Duration duration){
            return (Clock.currTime - time) > duration;
        }
        void updateTimestamp(ref SysTime time){
            time = Clock.currTime;
        }

        SysTime start_timestamp;

        auto stop = false;
        NodeAddress[Pubkey] node_addresses;

        void recordOwnInfo(string addrs){
            auto params = new HiBON;
            params["pkey"] = pubkey;
            params["address"] = addrs;
            auto doc = Document(params.serialize);
            auto json = doc.toJSON().toString();
            log("posting info to %s \n %s", opts.serverFileDiscovery.url ~ "/node/record", json);
            try{
                post(opts.serverFileDiscovery.url ~ "/node/record", ["value": json, "tag": opts.serverFileDiscovery.tag]);
            }catch(Exception e){
                log("ERROR: %s", e.msg);
            }
        }

        void eraseOwnInfo(){
            // auto params = new HiBON;
            // params["pkey"] = pubkey;
            log("posting info to %s", opts.serverFileDiscovery.url ~ "/node/erase");
            // post(opts.serverFileDiscovery.url ~ "/node/erase", ["value":(cast(string)params.serialize)]);
            post(opts.serverFileDiscovery.url ~ "/node/erase", ["value":(cast(string)pubkey), "tag": opts.serverFileDiscovery.tag]);
        }

        scope(exit){
            eraseOwnInfo();
        }

        void initialize(){
            try{
                auto read_buff = get(opts.serverFileDiscovery.url ~ "/node/storage?tag=" ~ opts.serverFileDiscovery.tag);
                // log("%s", cast(char[])read_buff);
                auto splited_read_buff = read_buff.split("\n");
                // log("%d", splited_read_buff.length);
                foreach(node_info_buff; splited_read_buff){
                    if(node_info_buff.length>0){
                        import std.json;
                        auto json = (cast(string)node_info_buff).parseJSON;
                        auto hibon = json.toHiBON;
                        auto doc = Document(hibon.serialize);
                        import tagion.hibon.HiBONJSON;
                        auto pkey_buff=doc["pkey"].get!Buffer;
                        auto pkey = cast(Pubkey)pkey_buff;
                        auto addr = doc["address"].get!string;
                        import tagion.utils.Miscellaneous : toHexString, cutHex;
                        auto node_addr = NodeAddress(addr, opts, true);
                        node_addresses[pkey]= node_addr;
                    }
                }
                log("initialized %d", node_addresses.length);
            }catch(Exception e){
                writeln("Er:", e.msg);
                log.fatal(e.msg);
            }
        }
        spawn(&handleAddrChanedEvent, node);
        spawn(&handleRechabilityChanged, node);
        node.SubscribeToAddressUpdated("addr_changed_handler");
        node.SubscribeToRechabilityEvent("rechability_handler");
        updateTimestamp(start_timestamp);
        bool is_online = false;
        string last_seen_addr = "";

        bool is_ready = false;
        do{
            receiveTimeout(
                500.msecs,
                (immutable(Pubkey) key, Tid tid){
                    log("looking for key: %s", key);
                    tid.send(node_addresses[key]);
                },
                (Control control){
                    if(control == Control.STOP){
                        log("stop");
                        stop = true;
                    }
                },
                (string updated_address){
                    last_seen_addr = updated_address;
                    if(is_online){
                        recordOwnInfo(updated_address);
                    }
                },
                (ServerRequestCommand cmd){
                    switch(cmd){
                        case ServerRequestCommand.BecomeOnline: {
                            is_online = true;
                            updateTimestamp(start_timestamp);
                            if(last_seen_addr!=""){
                                recordOwnInfo(last_seen_addr);
                            }
                            break;
                        }
                        case ServerRequestCommand.RequestTable: {
                            initialize();
                            auto address_book = new immutable AddressBook!Pubkey(node_addresses);
                            ownerTid.send(address_book);
                            break;
                        }
                        case ServerRequestCommand.BecomeOffline: {
                            eraseOwnInfo();
                        }
                        default: break;
                    }
                }
            );
            if(!is_ready && checkTimestamp(start_timestamp, opts.serverFileDiscovery.delay_before_start.msecs) && is_online){
                log("initializing");
                updateTimestamp(start_timestamp);
                is_ready = true;
                initialize();
                auto address_book = new immutable AddressBook!Pubkey(node_addresses);
                ownerTid.send(address_book);
            }
            if(is_ready && checkTimestamp(start_timestamp, opts.serverFileDiscovery.update.msecs)){
                log("updating");
                updateTimestamp(start_timestamp);
                initialize();
                auto address_book = new immutable AddressBook!Pubkey(node_addresses);
                ownerTid.send(address_book);
            }
        }while(!stop);
    }catch(Exception e){
        log("Exception: %s", e.msg);
        ownerTid.send(cast(immutable) e);
    }
}

void handleAddrChanedEvent(shared p2plib.Node node){
    register("addr_changed_handler", thisTid);

    do{
        receive(
            (immutable(ubyte)[] data){
                auto pub_addr = node.PublicAddress;
                writeln("Addr changed %s", pub_addr);
                if(pub_addr.length > 0){
                    auto addrinfo = node.AddrInfo();
                    ownerTid.send(addrinfo);
                }
            }
        );
    }while(true);
}

void handleRechabilityChanged(shared p2plib.Node node){
    register("rechability_handler", thisTid);
    do{
        receive(
            (immutable(ubyte)[] data){
                writeln("RECHABILITY CHANGED: %s", cast(string) data);
            }
        );
    }while(true);
}
