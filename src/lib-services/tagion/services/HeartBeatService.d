module tagion.services.HeartBeatService;

import core.thread;
import std.concurrency;

import tagion.Options;
import tagion.services.LoggerService;
import tagion.utils.Random;

import tagion.Base : Pubkey, Control;
import tagion.services.TagionService;
import tagion.gossip.EmulatorGossipNet;

void heartBeatServiceThread(immutable(Options) opts) { //immutable uint count_from, immutable uint N, immutable uint seed, immutable uint delay, immutable uint timeout) {
    // Set thread options
    set(opts);

    immutable tast_name="heatbeat";
//    register(tast_name, thisTid);
    log.register(tast_name);
//      immutable N=opts.nodes;
//      immutable delay=opts.delay;
//      immutable timeout=opts.timeout;
//      immutable uint count_from=opts.loops;

//    auto main_tid=ownerTid;

    Tid[] tids;
//    Tid[] scription_api_tids;
    Pubkey[]  pkeys;
//    immutable monitor_address = opts.url; //"127.0.0.1";

    version(Monitor) {
        auto network_socket_thread_id = spawn(&createSocketThread, opts.network_socket_port, monitor_address);
     //spawn(&createSocketThread, ThreadState.LIVE, monitor_port, monitor_ip_address, true);

//        register(format("network_socket_thread %s", opts.network_socket_port), network_socket_thread_id);
    }

//    immutable transcript_enable=opts.transcript.enable;

    scope(exit) {
        version(Monitor) {
            if ( network_socket_thread_id != Tid.init ) {
                log.writefln("Send prioritySend(Control.STOP) %s", options.network_socket_port);
                network_socket_thread_id.send(Control.STOP);
                auto control=receiveOnly!Control;
                if ( control == Control.END ) {
                    log.writeln("Closed network socket monitor.");
                }
                else {
                    log.writefln("Closed network socket monitor with unexpect control command %s", control);
                }
            }
        }

        log("----- Stop all tasks -----");
        foreach(i, ref tid; tids) {
            log("Send stop to %d", i);
            tid.prioritySend(Control.STOP);
        }
        log("----- Wait for all tasks -----");
        foreach(i, ref tid; tids) {
            auto control=receiveOnly!Control;
            if ( control == Control.END ) {
                log("Thread %d stopped %d", i, control);
            }
            else {
                log("Thread %d stopped %d unexpected control %s", i, control);
            }
        }
        log("----- Stop send to all -----");
//        log.close;
    }

    foreach(i;0..opts.nodes) {
        Options service_options=opts;
//        ushort monitor_port;
        if ( (!opts.monitor.disable) && ((opts.monitor.max == 0) || (i < opts.monitor.max) ) ) {
            service_options.monitor.port=cast(ushort)(opts.monitor.port + i);
        }
        service_options.node_id=cast(uint)i;
        //service_options.node_name=getname(service_options.node_id);
        immutable(Options) tagion_service_options=service_options;
//
//        immutable setup=immutable(EmulatorGossipNet.Init)(timeout, i, N, monitor_address, service_options.monitor.port, 1234);
//        auto tid=spawn(&(tagionServiceThread!EmulatorGossipNet), setup);
        auto tid=spawn(&(tagionServiceThread!EmulatorGossipNet), tagion_service_options);
//        register(getname(i), tid);
        tids~=tid;
        pkeys~=receiveOnly!(Pubkey);
        log("Start %d", pkeys.length);
    }

    log("----- Receive sync signal from nodes -----");

    log("----- Send acknowlege signals  num of keys=%d -----", pkeys.length);

    foreach(ref tid; tids) {
        foreach(pkey; pkeys) {
            tid.send(pkey);
        }
    }

    uint count = opts.loops;

    bool stop=false;

    if ( opts.sequential ) {
        Thread.sleep(1.seconds);


        log("Start the heart beat");
        uint node_id;
        uint time=opts.delay;
        Random!uint rand;
        rand.seed(opts.seed);
        while(!stop) {
            if ( !opts.infinity ) {
                log("count=%d", count);
            }
            Thread.sleep(opts.delay.msecs);

            tids[node_id].send(time, rand.value);
            if ( !opts.infinity ) {
                log("send time=%d to  %d", time, node_id);
            }

            time+=opts.delay;
            node_id++;
            if ( node_id >= tids.length ) {
                node_id=0;
            }

            if ( !opts.infinity ) {
                stop=(count==0);
                count--;
            }
        }
    }
    else {
        while(!stop) {
            if ( !opts.infinity ) {
                log("count=%d", count);
            }
            Thread.sleep(opts.delay.msecs);
            if ( !opts.infinity ) {
                stop=(count==0);
                count--;
            }
        }
    }
}
