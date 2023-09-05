/// Service for validating inputs sent via socket
/// [Documentation documents/architecture/InputValidator](https://docs.tagion.org/#/documents/architecture/InputValidator)
module tagion.services.inputvalidator;

import std.socket;
import std.stdio;
import std.algorithm : remove;

import core.time;

import tagion.actor;
import tagion.services.messages;
import tagion.logger.Logger;
import tagion.utils.pretend_safe_concurrency;
import tagion.script.StandardRecords;
import tagion.network.ReceiveBuffer;
import tagion.hibon.Document;
import tagion.hibon.HiBONJSON;
import tagion.hibon.HiBONRecord;
import tagion.communication.HiRPC;
import tagion.basic.Debug : __write;
import tagion.utils.JSONCommon;

import nngd;

@safe
struct InputValidatorOptions {
    string sock_addr;
    uint socket_select_timeout = 1000; // msecs
    void setDefault() nothrow {
        import tagion.services.options : contract_sock_path;

        sock_addr = contract_sock_path;
        socket_select_timeout = 1000;
    }

    mixin JSONCommon;
}

/** 
 *  InputValidator actor
 *  Examples: [tagion.testbench.services.inputvalidator]
 *  Sends: (inputDoc, Document) to receiver_task;
**/
struct InputValidatorService {
    void task(immutable(InputValidatorOptions) opts, string receiver_task) {
        auto rejected = submask.register("inputvalidator/reject");
        NNGSocket s = NNGSocket(nng_socket_type.NNG_SOCKET_PULL);
        ReceiveBuffer buf;
        // s.recvtimeout = opts.socket_select_timeout.msecs;
        const listening = s.listen(opts.sock_addr);
        if (listening == 0) {
            log("listening on addr: %s", opts.sock_addr);
        }
        else {
            log.error("Failed to listen on addr: %s, %s", opts.sock_addr, nng_errstr(listening));
            assert(0); // fixme
        }
        const recv = (scope void[] b) @trusted {
            size_t ret = s.receivebuf(cast(ubyte[]) b);
            return (ret < 0) ? 0 : cast(ptrdiff_t) ret;
        };
        setState(Ctrl.ALIVE);
        while (!thisActor.stop) {
            // Check for control signal
            const received = receiveTimeout(
                    Duration.zero,
                    &signal,
                    &ownerTerminated,
                    &unknown
            );
            if (received) {
                continue;
            }

            auto result = buf.append(recv);
            if (s.m_errno != nng_errno.NNG_OK) {
                log(rejected, "NNG_ERRNO", s.m_errno);
                continue;
            }

            // Fixme ReceiveBuffer .size doesn't always return correct lenght
            if (result.data.length <= 0) {
                log(rejected, "invalid_buf", result.size);
                continue;
            }

            Document doc = Document(cast(immutable) result.data);
            if (doc.isInorder && doc.isRecord!(HiRPC.Sender)) {
                locate(receiver_task).send(inputDoc(), doc);
            }
            else {
                log(rejected, "invalid_doc", doc);
            }
        }
    }
}

alias InputValidatorHandle = ActorHandle!InputValidatorService;
