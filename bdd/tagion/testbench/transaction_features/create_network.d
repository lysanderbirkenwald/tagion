module tagion.testbench.transaction_features.create_network;
// Default import list for bdd
import tagion.behaviour;
import tagion.hibon.Document;
import std.typecons : Tuple;
import tagion.testbench.tools.Environment;

import std.stdio;
import std.process;
import std.path;
import std.string;
import std.array;
import std.file;
import std.conv;
import core.thread;
import std.algorithm;

import tagion.testbench.transaction_features.create_wallets;
import tagion.testbench.transaction_features.create_dart;
import tagion.testbench.tools.utils : Genesis;
import tagion.testbench.tools.wallet;
import tagion.testbench.tools.network;

enum feature = Feature("Start network", []);

alias FeatureContext = Tuple!(CreateNetworkWithNAmountOfNodesInModeone, "CreateNetworkWithNAmountOfNodesInModeone",
    FeatureGroup*, "result");

@safe @Scenario("Create network with n amount of nodes in mode_one", [])
class CreateNetworkWithNAmountOfNodesInModeone
{

    GenerateDart dart;
    TagionWallet[] wallets;
    const Genesis[] genesis;
    const int number_of_nodes;
    string module_path;

    string[] node_logs;
    string[] node_darts;
    Pid[] pids;




    this(string module_name, GenerateDart dart, GenerateNWallets genWallets, const Genesis[] genesis, const int number_of_nodes)
    {
        this.dart = dart;
        this.wallets = genWallets.wallets;
        this.genesis = genesis;
        this.number_of_nodes = number_of_nodes;
        this.module_path = env.bdd_log.buildPath(module_name);
    }

    @Given("i have _wallets")
    Document _wallets()
    {
        check(wallets !is null, "No wallets available");

        return result_ok;
    }

    @Given("i have a dart with a genesis_block")
    Document genesisblock()
    {
        check(dart.dart_path.exists, "dart not found");
        check(dart.genesis_path.exists, "genesis not found");
        return result_ok;
    }

    @When("network is started")
    Document started() @trusted
    {
        const boot_path = module_path.buildPath("boot.hibon");

        // start all normal nodes
        for (int i = 1; i < number_of_nodes; i++)
        {
            immutable node_dart = module_path.buildPath(format("dart-%s.drt", i));
            immutable node_log = module_path.buildPath(format("node-%s.log", i));

        //     immutable node_command = [
        //         tools.tagionwave,
        //         "--net-mode=local",
        //         format("--boot=%s", boot_path),
        //         "--dart-init=true",
        //         "--dart-synchronize=true",
        //         format("--dart-path=%s", node_dart),
        //         format("--port=%s", 4000 + i),
        //         format("--transaction-port=%s", 10800 + i),
        //         format("--logger-filename=%s", node_log),
        //         "-N",
        //         number_of_nodes.to!string,
        //     ];

            Node node = Node(module_path, i, number_of_nodes);
            
            auto f = File("/dev/null", "w");

            // auto node_pid = spawnProcess(node_command, std.stdio.stdin, f, f);
            auto node_pid = node.start;
            node_darts ~= node_dart;
            node_logs ~= node_log;
            pids ~= node_pid;

        }
        // start master node
        immutable node_master_log = module_path.buildPath("node-master.log");

        Node node = Node(module_path, number_of_nodes, number_of_nodes, true);

        auto f = File("/dev/null", "w");

        auto node_master_pid = node.start;

        node_logs ~= node_master_log;
        node_darts ~= dart.dart_path;
        pids ~= node_master_pid;

        return result_ok;
    }

    @Then("the nodes should be in_graph")
    Document ingraph() @trusted
    {
        int sleep_before = 5;
        Thread.sleep(sleep_before.seconds);
        check(waitUntilInGraph(60, 1, "10801") == true, "in_graph not found in log");

        return result_ok;
    }

    @Then("the wallets should receive genesis amount")
    Document amount() @trusted
    {
        foreach (i, genesis_amount; genesis)
        {
            /* immutable cmd = wallets[i].update(); */
            /* check(cmd.status == 0, format("Error: %s", cmd.output)); */

            Balance balance = wallets[i].getBalance();
            check(balance.returnCode == true, "Error in updating balance");
            writefln("%s", balance);
            check(balance.total == genesis[i].amount, "Balance not updated");
        }
        // check that wallets were updated correctly
        return result_ok;
    }

}
