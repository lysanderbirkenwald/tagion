module tagion.mobile.mobilelog;
import std.file;
import std.path;

version(WRITE_LOGS) {
static string log_file;
}
version(WRITE_LOGS) 
@safe void write_log(const(string) message) pure nothrow {
    if (!__ctfe) { 
        debug {
            import std.stdio;
            if (log_file !is string.init && log_file.exists) {
                log_file.append(message);
            }
        }
    }
}
