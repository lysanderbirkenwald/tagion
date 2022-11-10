module tagion.testbench.sslserver;

import std.stdio;

import tagion.behaviour.Behaviour;
import tagion.tools.Basic;

import tagion.testbench.network;
import tagion.network.SSLOptions;
import tagion.services.Options;
import tagion.testbench.tools.TestMain;
import tagion.testbench.Environment;

void setDefault(ref SSLOptions options, const Options opt) {
    options = opt.transaction.service;
}

mixin Main!_main;

int _main(string[] args) {
    auto setup = mainSetup!SSLOptions("sslserver", &setDefault);
    int result = testMain(setup, args);
    env.writeln;
    return result;
}
