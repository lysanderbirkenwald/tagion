/// time type wrapped on stdtime in phobos
module tagion.utils.StdTime;

import std.datetime;
import std.typecons : Typedef;

enum SDT = "SDT";

alias sdt_t = Typedef!(long, long.init, SDT);

@safe
sdt_t currentTime() {
    // This function throws on some platforms only apparently
    return sdt_t(Clock.currStdTime);
}

@safe
string toText(const sdt_t time) {
    SysTime sys_time = SysTime(cast(const long) time);
    return sys_time.toISOExtString;
}
