module tagion.testbench.hashgraph_test;

import std.conv;
import std.file : mkdirRecurse;
import std.format;
import std.path : buildPath;
import std.stdio;
import tagion.behaviour.Behaviour;
import tagion.testbench.hashgraph;
import tagion.testbench.tools.Environment;
import tagion.tools.Basic;

mixin Main!(_main);

int _main(string[] args) {
    const module_path = env.bdd_log.buildPath(__MODULE__);
    mkdirRecurse(module_path);
    writeln(args);
    stdout.flush;
    const node_amount = args[1].to!uint;
    const calls = args[2].to!uint;
    string[] node_names;
    foreach (i; 0 .. node_amount) {
        node_names ~= format("Node%d", i);
    }

    auto hashgraph_sync_network_feature = automation!(synchron_network);
    hashgraph_sync_network_feature.StartNetworkWithNAmountOfNodes(node_names, calls, module_path);
    auto hashgraph_sync_network_context = hashgraph_sync_network_feature.run();
    return 0;
}
