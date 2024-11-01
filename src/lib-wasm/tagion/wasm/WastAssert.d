module tagion.wasm.WastAssert;

import std.outbuffer;
import tagion.basic.Types;
import tagion.hibon.HiBONRecord;
import tagion.wasm.WasmWriter;

@safe
struct Assert {
    enum Method {
        Return,
        Invalid,
        Return_nan,
        Trap,
    }

    string name;
    Method method;
    Buffer invoke;
    @optional Buffer result;
    @optional string message;

    mixin HiBONRecord;
    void serialize(ref OutBuffer bout) const {
        bout.write(toDoc.serialize);
    }
}

@safe
struct SectionAssert {
    Assert[] asserts;
    mixin HiBONRecord;
}
