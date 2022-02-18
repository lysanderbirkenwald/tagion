module tagion.behaviour.Behaviour;

import std.traits;
import std.format;
import std.typecons;

struct Feature {
    string description;
    string[] comments;
}

struct Given {
    string description;
}

struct And {
    string description;
}

struct When {
    string description;
}

struct Then {
    string description;
}

alias MemberSequency=Tuple!(string, "member", string, "goal");
const(MemberSequency[]) memberSequency(T)() if (is(T==class) || is(T==struct)) {
//    string[] result;
    MemberSequency[] result;
    alias getMemberType(alias Type, string name) = typeof(__traits(getMember, T, name));
    alias member1=getMemberType!(T, "request_cash");
    pragma(msg, "member1 ", member1);
//    T
    static foreach(name; __traits(allMembers, T)) {{
            enum code=format!q{alias member=%s.%s;}(T.stringof, name);
            pragma(msg,code);
            mixin(code);
            T elem;
//            pragma(msg, __traits(identifier, member));
            //          static if (__traits(compile, typeof(member))) {
            static if (__traits(compiles, typeof(member))) {
//                alias memberType=typeof(member);
//                pragma(msg, "member ", name, " ", typeof(member));
                static if (hasUDA!(member, Given)) {
                    result~=MemberSequency(name, Given);
                    pragma(msg, name, " has ", Given);
                }
                else static if (hasUDA!(member, And)) {
                    pragma(msg, name, " has ", And);
                }
                else static if (hasUDA!(member, When)) {
                    pragma(msg, name, " has ", When);
                }
                else static if (hasUDA!(member, Then)) {
                    pragma(msg, name, " has ", Then);
                }
            }
        }}
    return result;
}
version(unittest) {
    // Behavioral examples
    @Feature("Some awesome feature should print some cash out of the blue")
        class Some_awesome_feature {
            @Given("the card is valid")
            bool is_valid() {
                return false;
            }
            @And("the account is in credit")
            bool in_credit() {
                return false;
            }
            @And("the dispenser contains cash")
            bool contains_cash() {
                return false;
            }
            @When("the Customer request cash")
            bool request_cash() {
                return false;
            }
            @Then("the account is debited")
            bool is_debited() {
                return false;
            }
            @And("the cash is dispensed")
            bool is_dispensed() {
                return false;
            }
        }

    @Feature("Some awesome feature should print some cash out of the blue")
        class Some_awesome_feature_not_ordered {
            @Then("the account is debited")
            bool is_debited() {
                return false;
            }
            @And("the cash is dispensed")
            bool is_dispensed() {
                return false;
            }
            @When("the Constumer request cash")
            bool request_cash() {
                return false;
            }
            @Given("that the card is valid")
            bool is_valid() {
                return false;
            }
            @And("the account is in credit")
            bool in_credit() {
                return false;
            }
            @And("the dispenser contains cash")
            bool contains_cash() {
                return false;
            }
        }
}




unittest {
    import std.stdio;
    import std.algorithm.iteration : map, joiner;
    import std.algorithm.comparison : equal;
    import std.range : zip, only;
    import std.typecons;
    import std.array;
    pragma(msg, __traits(allMembers, Some_awesome_feature));
    alias member=typeof(__traits(getMember, Some_awesome_feature, "is_debited"));

    pragma(msg, "member ", member);
//    alias monitor=typeof(__traits(getMember, Some_awesome_feature, "Monitor"));
//    pragma(msg, "member ", getUDAs!member);
//    pragma(msg, __traits(GetM
    alias SomeFormat=format!(Some_awesome_feature.stringof~".%s", string);
    writeln(SomeFormat("Hugo"));
    const expected=
        zip(
            ["is_valid", "in_credit", "contains_cash", "request_cash", "is_debited", "is_dispensed"],
            ["Given", "And", "And", "When", "And", "Then"]
        )
        .map!(a => tuple(SomeFormat(a[0]), a[1]))
//        .joiner
        .array;
    writefln("expected=%s", expected);
    assert(equal(memberSequency!Some_awesome_feature,
            expected));
        // ["is_valid", "in_credit", "contains_cash", "request_cash", "is_debited", "is_dispensed"]);



}
