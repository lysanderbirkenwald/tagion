import std.stdio;
import std.conv;
import std.string;
import std.concurrency;
import core.thread;
import std.datetime.systime;
import std.uuid;
import std.regex;
import std.exception;

import nngd;
import nngtestutil;


// REP
void server_worker(string url)
{
    int k = 0, p = 0;
    const int MAXREQ = 1000;
    string line;
    int rc;
    auto ctr = regex(r" ([0-9]+)$");
    NNGSocket s = NNGSocket(nng_socket_type.NNG_SOCKET_REP);
    s.sendtimeout = msecs(1000);
    s.recvtimeout = msecs(1000);
    s.sendbuf = 4096;
    log("REP: listening");
    rc = s.listen(url);
    enforce(rc == 0);
    log(nngtest_socket_properties(s,"REP"));
    while( p < 4 ){
        auto ss = s.receive!string();
        if(s.errno != 0){
            log("REP: RECV ERROR: " ~ toString(s.errno));
            continue;
        }
        line = ss;
        k++;
        log("REP: RECV: " ~ line);
        auto rres = matchFirst(line, ctr);
        line = format("REPLY(%d) = %s",k,line);
        if(!rres.empty){
            auto i = to!int(rres[1]);
            if(i>MAXREQ){
                line = "END";
                p++;
            }
        }
        rc = s.send!string(line);
        if(rc != 0){
            log("REP: SEND ERROR: " ~ toString(rc));
        }else{
            log("REP: SENT: " ~ line);
        }
    }
    log("REP: bye!");
}


// REQ
void client_worker(string url, string tag)
{
    int rc;
    string line;
    int k = 0;
    NNGSocket s = NNGSocket(nng_socket_type.NNG_SOCKET_REQ);
    s.recvtimeout = msecs(1000);
    while(1){
        log("REQ("~tag~"): to dial...");
        rc = s.dial(url);
        if(rc == 0) break;
        log("REQ("~tag~"): Dial error: ",toString(rc));
        if(rc == nng_errno.NNG_ECONNREFUSED){
            nng_sleep(msecs(100));
            continue;
        }
        enforce(rc == 0);
    }
    log(nngtest_socket_properties(s,"REQ("~tag~")"));
    while(1){
        k++;
        line = format("Client(%s) request %d", tag, k);            
        rc = s.send!string(line);
        enforce(rc == 0);
        log("REQ("~tag~"): SENT: " ~ line);
        auto str = s.receive!string();
        if(s.errno == 0){
            log(format("REQ("~tag~") RECV [%03d]: %s", str.length, str));
        }else{
            log("REQ("~tag~"): Error string: " ~ toString(s.errno));
        }    
        if(str == "END")
            break;
    }
    log("REQ("~tag~"): bye!");
}


int main()
{
    writeln("Hello NNGD!");
    writeln("Simple req-rep test in sync mode");

    string uri = "tcp://127.0.0.1:31200";
    immutable string[] tags = ["TAG0", "TAG1", "TAG2", "TAG3"];

    auto tid01 = spawn(&server_worker, uri);         // server 
    auto tid02 = spawn(&client_worker, uri, tags[0]);      // client for exact tag
    auto tid03 = spawn(&client_worker, uri, tags[1]);      // ...
    auto tid04 = spawn(&client_worker, uri, tags[2]);
    auto tid05 = spawn(&client_worker, uri, tags[3]);
    thread_joinAll();

    return 0;
}

