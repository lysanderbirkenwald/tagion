module tagion.testbench.tools.BDDOptions;

import tagion.utils.JSONCommon;
import tagion.testbench.tools.utils : Genesis;
import tagion.testbench.tools.BDDConstants;

struct BDDOptions
{
    string scenario_name;

    BDDConstants constants;

    mixin JSONCommon;

    struct GenesisWallets
    {
        uint number_of_wallets;
        Genesis[] wallets;
        mixin JSONCommon;
    }

    GenesisWallets genesis_wallets;

    struct Network
    {
        uint increase_port;
        uint tx_increase_port;
        uint number_of_nodes;

        mixin JSONCommon;
    }

    Network network;

    mixin JSONConfig;
}

void setDefaultBDDOptions(ref BDDOptions bdd_options)
{
    with (bdd_options)
    {
        bdd_options.scenario_name = "NAME";
        with (bdd_options.constants)
        {
            MAX_EPOCHS = 8;
        }
        with (bdd_options.genesis_wallets)
        {
            number_of_wallets = 7;
            wallets = [
                Genesis(1, 10_000),
                Genesis(1, 10_000),
                Genesis(1, 10_000),
                Genesis(1, 10_000),
                Genesis(1, 10_000),
                Genesis(1, 10_000),
                Genesis(1, 10_000),
            ];
        }
        with (bdd_options.network)
        {
            increase_port = 4000;
            tx_increase_port = 10800;
            number_of_nodes = 11;
        }

    }
}
