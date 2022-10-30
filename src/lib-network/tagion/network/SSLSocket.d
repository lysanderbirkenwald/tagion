module tagion.network.SSLSocket;

import core.stdc.stdio;
import core.stdc.string : strerror;

import std.socket;
import std.range.primitives : isBidirectionalRange;
import std.string : format, toStringz;
import std.typecons : Tuple;
import std.array : join;
import std.algorithm.iteration : map;

import tagion.network.SSLSocketException;
import tagion.network.SSL;

import io = std.stdio;

import tagion.basic.Debug : __write;

enum EndpointType {
    Client,
    Server
}

version (none) enum SSL_CB_POINTS : int {
    CB_LOOP = 0x1,
    CB_EXIT = 0x2,
    CB_READ = CB_EXIT * 2,
    CB_WRITE = CB_READ * 2,
    HANDSHAKE_START = 0x10,
    HANDSHAKE_DONE = HANDSHAKE_START * 2,
    ST_CONNECT = 0x1000,
    ST_CONNECT_LOOP,
    ST_CONNECT_EXIT,
    ST_ACCEPT = ST_CONNECT * 2,
    CB_ACCEPT_LOOP,
    CB_ACCEPT_EXIT,
    CB_ALERT = ST_ACCEPT * 2,
    CB_READ_ALERT = CB_ALERT + CB_READ,
    CB_WRITE_ALERT = CB_ALERT + CB_WRITE
}

/++
 Socket for OpenSSL
+/
@safe
class SSLSocket : Socket {
    enum ERR_TEXT_SIZE = 256;
    //alias SSL_error_text_t = char[ERR_TEXT_SIZE];
    protected {
        SSL* _ssl;
        static SSL_CTX* _ctx;

        //Static are used as default as context. A setter/argu. in cons. for the context
        //could be impl. if diff. contexts for diff SSL are needed.
        //static SSL_CTX* client_ctx;
        //static SSL_CTX* server_ctx;
    }

    /++
     The client use this configuration by default.
     +/
    protected final void _init(bool verifyPeer, EndpointType et) {
        //        checkContext(et);
        _ssl = SSL_new(_ctx);
        __write("et=%s", et);
        if (et is EndpointType.Client) {
            SSL_set_fd(_ssl, this.handle);
            if (!verifyPeer) {
                SSL_set_verify(_ssl, SSL_VERIFY_NONE, null);
            }
        }
    }

    ~this() {
        //close;
        shutdown(SocketShutdown.BOTH);
        SSL_free(_ssl);
    }

    static this() {
        synchronized {
            _ctx = SSL_CTX_new(TLS_client_method());
        }
    }

    version (none) protected void checkContext(EndpointType et)
    out {
        assert(_ctx);
    }
    do {
        synchronized {
            if (_ctx is null)
                _ctx = SSL_CTX_new(TLS_client_method());

            //Maybe implement more versions....
            if (et is EndpointType.Client) {
                if (client_ctx is null) {
                    client_ctx = SSL_CTX_new(TLS_client_method());
                }
            }
            else if (et is EndpointType.Server) {
                if (server_ctx is null) {
                    server_ctx = SSL_CTX_new(TLS_server_method());
                }
            }
        }

    }

    static string errorText(const long error_code) @trusted nothrow {
        import core.stdc.string : strlen;
        import std.exception : assumeUnique;

        auto result = new char[ERR_TEXT_SIZE];
        ERR_error_string_n(error_code, result.ptr, result.length);
        return assumeUnique(result[0 .. strlen(result.ptr)]);
    }

    alias SSL_Error = Tuple!(long, "error_code", string, "msg");

    static const(SSL_Error[]) getErrors() nothrow {
        long error_code;
        SSL_Error[] result;
        while ((error_code = ERR_get_error) != 0) {
            result ~= SSL_Error(error_code, errorText(error_code));
        }
        return result;
    }

    static string getAllErrors() {
        return getErrors
            .map!(err => format("Err %d: %s", err.error_code, err.msg))
            .join("\n");
    }
    /++
     Configure the certificate for the SSL
     +/
    @trusted
    void configureContext(string certificate_filename, string prvkey_filename) {
        import std.file : exists;

        ERR_clear_error;
        check(certificate_filename.exists, format("Certification file '%s' not found", certificate_filename));
        check(prvkey_filename.exists, format("Private key file '%s' not found", prvkey_filename));

        if (SSL_CTX_use_certificate_file(_ctx, certificate_filename.toStringz,
                SSL_FILETYPE_PEM) <= 0) {
            throw new SSLSocketException(format("SSL Certificate: %s", getAllErrors));
        }

        if (SSL_CTX_use_PrivateKey_file(_ctx, prvkey_filename.toStringz, SSL_FILETYPE_PEM) <= 0) {
            throw new SSLSocketException(format("SSL private key:\n %s", getAllErrors));
        }
        if (SSL_CTX_check_private_key(_ctx) <= 0) {
            throw new SSLSocketException(format("Private key not set correctly:\n %s", getAllErrors));
        }
    }

    /++
     Cleans the SSL error que
     +/
    static void clearError() {
        ERR_clear_error();
    }

    /++
     Connect to an address
     +/
    override void connect(Address to) {
        super.connect(to);
        const res = SSL_connect(_ssl);
        check_error(res, true);
    }

    /++
     Send a buffer to the socket using the socket result
     +/
    @trusted
    override ptrdiff_t send(const(void)[] buf, SocketFlags flags) {
        auto res_val = SSL_write(_ssl, buf.ptr, cast(int) buf.length);
        // const ssl_error = cast(SSLErrorCodes) SSL_get_error(_ssl, res_val);
        check_error(res_val);
        return res_val;
    }

    /++
     Send a buffer to the socket with no result
     +/
    override ptrdiff_t send(const(void)[] buf) {
        return send(buf, SocketFlags.NONE);
    }

    version (none) version (WOLFSSL) {
        static void check_WOLFSSL_error(ref SSLErrorCodes error) {
            io.writeln("<" ~ str_error(error) ~ '>');
            with (SSL_ErrorCodes) switch (cast(wolfSSL_ErrorCodes) error) {
            case SOCKET_ERROR_E:
                error = SSLErrorCodes.SSL_ERROR_SYSCALL;
                return;
            default:
                return;
            }
        }
    }

    /* Helper function to convert a ssl_error to an exception
     * This function should only called after an ssl function call
     * Throws: a SSLSocketException if the _ssl handler contains an error
     * Params:
     *   ssl_ret = Return code for SSL (ssl_ret > 0) means no error
     *   false = Enable ignore temporary errors for (Want to read or write)
     */
    protected void check_error(const int ssl_ret, const bool check_read_write = false) const {
        const ssl_error = cast(SSLErrorCodes) SSL_get_error(_ssl, ssl_ret);
        __write("ssl_error = %s ret = %d", ssl_error, ssl_ret);
        with (SSLErrorCodes) final switch (ssl_error) {
        case SSL_ERROR_NONE:
            // Ignore
            break;
        case SSL_ERROR_WANT_WRITE,
        SSL_ERROR_WANT_READ:
            if (check_read_write) {
                throw new SSLSocketException(str_error(ssl_error), ssl_error);
            }
            break;
        case SSL_ERROR_WANT_X509_LOOKUP,
            SSL_ERROR_SYSCALL,
            SSL_ERROR_ZERO_RETURN,
            SSL_ERROR_WANT_CONNECT,
            SSL_ERROR_WANT_ACCEPT,
            SSL_ERROR_WANT_ASYNC,
            SSL_ERROR_WANT_ASYNC_JOB,
        SSL_ERROR_SSL:
            throw new SSLSocketException(str_error(ssl_error), ssl_error);
            break;
        }

    }

    /++
     Returns:
     pending bytes in the socket que
     +/
    uint pending() {
        const result = SSL_pending(_ssl);
        return cast(uint) result;
    }

    /++
     Receive a buffer from the socket using the flags
     +/
    @trusted
    override ptrdiff_t receive(void[] buf, SocketFlags flags) {
        const res_val = SSL_read(_ssl, buf.ptr, cast(uint) buf.length);
        check_error(res_val);
        return res_val;
    }

    /++
     Receive a buffer from the socket with not flags
     +/
    override ptrdiff_t receive(void[] buf) {
        return receive(buf, SocketFlags.NONE);
    }

    version (none) {
        @trusted
        int receiveNonBlocking(void[] buf, ref int pending_in_buffer)
        in {
            assert(!this.blocking);
        }
        do {
            int res = SSL_read(_ssl, buf.ptr, cast(int) buf.length);

            check_error(res);
            pending_in_buffer = SSL_pending(_ssl);

            return res;
        }
    }

    version (none) static string errorMessage(const SSLErrorCodes ssl_error) {
        return format("SSL Error: %s. SSL error code: %d", ssl_error, ssl_error);
    }

    /++
     Returns:
     the SSL system error message
     +/
    @trusted
    static string str_error(const int errornum) {
        const str = strerror(errornum);
        import std.string : fromStringz;

        return fromStringz(str).idup;
    }

    version (none) @trusted
    static string err_string() {
        enum ERROR_LENGTH = 0x100;
        const error_code = ERR_get_error;
        scope char[ERROR_LENGTH] err_text;
        ERR_error_string_n(ERR_get_error, err_text.ptr, ERROR_LENGTH);
        import std.string : fromStringz;

        return fromStringz(err_text.ptr).idup;
    }

    version (none) static bool isKnownError(ref const string error_descr) {
        import std.algorithm;

        return error_descr.startsWith("Unknown error ") == 0;
    }

    /++
       Create a SSL socket from a socket
       Returns:
       true of the ssl_socket is succesfully created
       a ssl_client for the client
       Params:
       client = Standard socket (non ssl socket)
       ssl_socket = The SSL
    +/
    bool acceptSSL(ref SSLSocket ssl_client, Socket client) {
        if (ssl_client is null) {
            if (!client.isAlive) {
                client.close;
                io.writeln(" ------------- 1 ------------ ");
                throw new SSLSocketException("Socket could not connect to client. Socket closed.");
            }
            client.blocking = false;
            ssl_client = new SSLSocket(client.handle, EndpointType.Server, client.addressFamily);
            const fd_res = SSL_set_fd(ssl_client.getSSL, client.handle);
            if (!fd_res) {
                return false;
            }
        }

        auto c_ssl = ssl_client.getSSL;

        const res = SSL_accept(c_ssl);
        bool accepted;

        const ssl_error = cast(SSLErrorCodes) SSL_get_error(c_ssl, res);

        with (SSLErrorCodes) switch (ssl_error) {
        case SSL_ERROR_NONE:
            accepted = true;
            break;

        case SSL_ERROR_WANT_READ,
        SSL_ERROR_WANT_WRITE:
            // Ignore
            break;
        case SSL_ERROR_SSL,
            SSL_ERROR_WANT_X509_LOOKUP,
            SSL_ERROR_SYSCALL,
        SSL_ERROR_ZERO_RETURN:
            io.writefln(" ------------ 2 ------------  %s", ssl_error);
            throw new SSLSocketException(str_error(ssl_error), ssl_error);
            break;
        default:
            io.writeln(" ------------- 3 ----------- ");
            throw new SSLSocketException(format("SSL Error. SSL error code: %d.", ssl_error),
                    SSL_ERROR_SSL);
            break;
        }
        return !SSL_pending(c_ssl) && accepted;
    }

    /+
    version (WOLFSSL) {
        static void processingWolfSSLError(WOLFSSL_ErrorCodes _error) {
            switch (_error) {
            case WOLFSSL_ErrorCodes.SOCKET_ERROR_E:
            case WOLFSSL_ErrorCodes.SIDE_ERROR:
                throw new SSLSocketException(str_error(_error), SSLErrorCodes.SSL_ERROR_SSL);
            default:
                return;
            }
        }
    }
+/
    /++
       Reject a client connect and close the socket
     +/
    void rejectClient() {
        auto client = super.accept();
        client.close();
    }

    /++
     Disconnect the socket
     +/
    version (none) void disconnect() nothrow {
        if (_ssl !is null) {
            //SSL_free(_ssl);
            //  _ssl = null;
        }

        if ((client_ctx !is null || server_ctx !is null) &&
                client_ctx !is _ctx &&
                server_ctx !is _ctx &&
                _ctx !is null) {

            //   SSL_CTX_free(_ctx);
            //   _ctx = null;
        }
        super.close();
    }

    /++
     Returns:
     the SSL system handler
     +/
    @trusted @nogc
    package SSL* getSSL() pure nothrow {
        return this._ssl;
    }

    /++
     Constructs a new socket
     +/
    this(AddressFamily af,
            EndpointType et,
            SocketType type = SocketType.STREAM,
            bool verifyPeer = true) {
        ERR_clear_error;
        super(af, type);
        _init(verifyPeer, et);
    }

    /// ditto
    this(socket_t sock, EndpointType et, AddressFamily af) {
        ERR_clear_error;
        super(sock, af);
        _init(true, et);
    }

    version (none) static private void reset() {
        if (server_ctx !is null) {
            //  SSL_CTX_free(server_ctx);
            //  server_ctx = null;
        }
        if (client_ctx !is null) {
            //  SSL_CTX_free(client_ctx);
            //  client_ctx = null;
        }
    }

    version (none) static ~this() {
        reset();
    }

    unittest {
        //    static _main() {
        import std.array;
        import std.string;
        import std.file;
        import std.exception : assertNotThrown, assertThrown, collectException;
        import tagion.basic.Basic : fileId;
        import std.stdio;

        import tagion.basic.Debug;

        immutable cert_path = testfile(__MODULE__ ~ ".pem");
        immutable key_path = testfile(__MODULE__ ~ ".key.pem");
        immutable stab = "stab";

        import tagion.network.SSLOptions;
        const OpenSSL ssl_options = {
            certificate: cert_path, /// Certificate file name
            private_key: key_path, /// Private key
            key_size: 1024, /// Key size (RSA 1024,2048,4096)
            days: 1, /// Number of days the certificate is valid
            country: "UA", /// Country Name two letters
            state: stab, /// State or Province Name (full name)
            city: stab, /// Locality Name (eg, city)
            organisation: stab, /// Organization Name (eg, company)
            unit: stab, /// Organizational Unit Name (eg, section)
            name: stab, /// Common Name (e.g. server FQDN or YOUR name)
            email: stab, /// Email Address

        
        };
        configureOpenSSL(ssl_options);

        //! [Waiting for first acception]
        {
            SSLSocket item = new SSLSocket(AddressFamily.UNIX, EndpointType.Server);
            SSLSocket ssl_client = new SSLSocket(AddressFamily.UNIX, EndpointType.Client);
            Socket client = new Socket(AddressFamily.UNIX, SocketType.STREAM);
            bool result; // = false;
            version (none)
                scope (exit) {
                    SSLSocket.reset;
                }
            const exception = collectException!SSLSocketException(
                    item.acceptSSL(ssl_client, client), result);
            assert(exception !is null);
            assert(exception.error_code == SSLErrorCodes.SSL_ERROR_SSL);
            assert(!result);
        }

        //! [File reading - incorrect certificate]
        {
            __write("incorrect certificate");
            SSLSocket testItem_server = new SSLSocket(AddressFamily.UNIX, EndpointType.Server);
            scope (exit) {
                testItem_server.close;
            }
            version (none)
                scope (exit) {
                    SSLSocket.reset;
                }
            assert(testItem_server !is null);
            __write("incorrect certificate Before END");
            assertThrown!SSLSocketException(
                    testItem_server.configureContext("_", "_"));
            __write("incorrect certificate END");
        }

        //! [File reading - empty path]
        {

            __write("empty path");
            SSLSocket testItem_server = new SSLSocket(AddressFamily.UNIX, EndpointType.Server);
            scope (exit) {
                testItem_server.close;
            }
            string empty_path = "";
            version (none)
                scope (exit) {
                    SSLSocket.reset;
                }
            __write("empty path before END");
            assertThrown!SSLSocketException(
                    testItem_server.configureContext(empty_path, empty_path)
            );
            __write("empty path END");
            //SSLSocket.reset();
        }

        //! [file loading correct]
        {
            __write("correct");
/*
            string cert_path;
            string key_path;
            optionGenKeyFiles(cert_path, key_path);
*/
            SSLSocket testItem_server = new SSLSocket(AddressFamily.UNIX, EndpointType.Server);
            scope (exit) {
                testItem_server.close;
            }
            version (none)
                scope (exit) {
                    SSLSocket.reset;
                }
            __write("correct before END");
            assertNotThrown!SSLSocketException(
                    testItem_server.configureContext(cert_path, key_path)
            );
            __write("correct END");
            //SSLSocket.reset();
        }

        //! [file loading key incorrect]
        {
/*
            string cert_path, stub;
            optionGenKeyFiles(cert_path, stub);
*/
            auto false_key_path = cert_path;
            SSLSocket testItem_server = new SSLSocket(AddressFamily.UNIX, EndpointType.Server);
            version (none)
                scope (exit) {
                    SSLSocket.reset;
                }
            const exception = collectException!SSLSocketException(
                    testItem_server.configureContext(cert_path, false_key_path)
            );
            assert(exception !is null);
            __write("key incorrect before END");
            assert(exception.error_code == SSLErrorCodes.SSL_ERROR_NONE);
            //          SSLSocket.reset();
            __write("key incorrect END");
        }

        //! [correct acception]
        {
            SSLSocket empty_socket = null;
            SSLSocket ssl_client = new SSLSocket(AddressFamily.UNIX, EndpointType.Client);
            Socket socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
            scope (exit) {
                ssl_client.close;
                socket.close;
            }
            bool result;
            version (none)
                scope (exit) {
                    SSLSocket.reset;
                }
            const exception = collectException!SSLSocketException(
                    result = ssl_client.acceptSSL(empty_socket, socket)
            );
            io.writefln("SSL_ERROR error_code=%s %d <%d>", exception.error_code,
                    cast(int) exception.error_code, cast(int) SSLErrorCodes.SSL_ERROR_SYSCALL);
            assert(exception !is null);
            assert(exception.error_code == SSLErrorCodes.SSL_ERROR_SSL);
            //assert(exception.error_code == SSLErrorCodes.SSL_ERROR_SYSCALL);
            assert(!result);
        }
   }
}

version (unitmain) void main() {
    SSLSocket._main;
}
