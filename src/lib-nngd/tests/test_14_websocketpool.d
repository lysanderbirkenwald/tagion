import std.stdio;
import std.conv;
import std.string;
import std.concurrency;
import core.thread;
import std.datetime.systime;
import std.path;
import std.file;
import std.uuid;
import std.regex;
import std.json;
import std.exception;
import std.process;

import nngd;
import nngtestutil;

struct ws_device {
    Tid tid;
    WebSocket *ws;
    void  *ctx;
}

shared ws_device[string] ws_devices;

static void ws_fiber ( string sid ) {
    int rc;
    int attempts = 0;
    int i = 0;
    WebSocket *ws = cast(WebSocket*)ws_devices[sid].ws;
    void *ctx = cast(void*)ws_devices[sid].ctx;
    log("WS: connected ", ws.sid);
    scope(exit){
        ws_devices.remove(sid);
    }
    while (!ws.closed) {
        receiveTimeout( 10.msecs,
            (string s){
                ws.send(cast(ubyte[])("WSF: "~sid~" CMD: "~s));
                if(s == "close"){
                    ws.close();
                }
            }
        );    
        ws.send(cast(ubyte[])("WSF: "~sid~" TICK: "~to!string(i)));
        i++;
        Thread.sleep(100.msecs);
    }
}

void onaccept_handler ( WebSocket *ws, void *ctx ){
    log("===> ONACCEPT handler: " ~ ws.sid);
    auto s = `{"hello":"ws", "sid":"`~ ws.sid ~`"}`;
    ws.send(cast(ubyte[])s.dup);
    auto sid = ws.sid;
    if(sid in ws_devices){
        log("Already cached socket: ", sid);
        return;
    }
    ws_device d = {
        ws: ws,
        ctx: ctx
    };
    ws_devices[sid] = cast(shared ws_device)d;
    auto tid =  spawn(&ws_fiber, sid);
    ws_devices[sid].tid = cast(shared(Tid))tid;
    log("WS: D0");
}   

void onmessage_handler ( WebSocket *ws, ubyte[] data, void *ctx ){
    auto sid = ws.sid;
    log("===> ONMESSAGE handler: " ~ sid);
    log("RECV: " ~ cast(string)data);
    try{
        if(sid in ws_devices){
            log("Sent to TID:");
            send(cast(Tid)ws_devices[sid].tid, cast(string)data);
        }
    } catch(Throwable e) {
        error(dump_exception_recursive(e, "Onmessage handler"));
    }        
}   

void onclose_handler( WebSocket *ws, void *ctx ){
    log("===> ONCLOSE handler: " ~ ws.sid);
}

void onerror_handler(WebSocket *ws, int err, void *ctx ){
    log("===> ONERROR handler: " ~ ws.sid ~ " : " ~ to!string(err));
}

int
main()
{
    int rc;
    
    const uri = "ws://127.0.0.1:8034";

    log("TEST ---------------------------------------------------  WS SERVER ");

    try{
        WebSocketApp wsa = WebSocketApp(uri, &onaccept_handler, &onclose_handler, &onerror_handler, &onmessage_handler, null );
        wsa.start();
        nng_sleep(300.msecs);
        auto res = executeShell("timeout 2 uwsc -i -s -t data.txt ws://127.0.0.1:8034 2>&1");
        assert(res.status == 124);
        assert(indexOf(res.output,"Websocket connected") == 0);
        assert(indexOf(res.output,`hello`) == 127);
        nng_sleep(2000.msecs);
    } catch(Throwable e) {
        error(dump_exception_recursive(e, "Main"));
    }        
    
    log("Bye!");
    return populate_state(14, "Websocket pool tests");
}



