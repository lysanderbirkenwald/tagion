module tagion.behaviour.BehaviourUnittestWithCtor;

import tagion.behaviour.BehaviourFeature;

/// This module is only use to support the unittest
version (unittest)
{
    import tagion.hibon.HiBON;
    import tagion.hibon.Document;
    import std.format;
    import std.process;

    immutable(string) REPOROOT;
    shared static this()
    {
        REPOROOT = environment.get(REPOROOT.stringof, null);
        assert(REPOROOT, format!"%s must be defined"(REPOROOT.stringof));
    }

    enum feature = Feature("Some awesome feature should print some cash out of the blue");
    // Behavioral examples
    @safe
    @Scenario("Some awesome money printer")
    class Some_awesome_feature
    {
        static Document result(string test)
        {
            auto h = new HiBON;
            h["test"] = test;
            return Document(h);
        }

        uint count;
        string text;
        this(const uint count, string text) {
            this.count = count;
            this.text = text;
        }

        @Given("the card is valid")
        Document is_valid()
        {
            count++;
            return result(__FUNCTION__);
        }

        @Given("the account is in credit")
        Document in_credit()
        {
            count++;
            return result(__FUNCTION__);
        }

        @Given("the dispenser contains cash")
        Document contains_cash()
        {
            count++;
            return result(__FUNCTION__);
        }

        @When("the Customer request cash")
        Document request_cash()
        {
            count++;
            return result(__FUNCTION__);
        }

        @Then("the account is debited")
        Document is_debited()
        {
            count++;
            return result(__FUNCTION__);
        }

        @Then("the cash is dispensed")
        Document is_dispensed()
        {
            count++;
            return result(__FUNCTION__);
        }

        @But("if the Customer does not take his card, then the card must be swollowed")
        Document swollow_the_card() {
            count++;
            return result(__FUNCTION__);
        }

        void helper_function()
        {
        }
    }

}
