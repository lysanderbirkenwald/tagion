module tagion.testbench.epoch_creator;

import tagion.behaviour.Behaviour;
import tagion.testbench.services;
import tagion.services.epoch_creator;
import tagion.tools.Basic;
import core.time;

mixin Main!(_main);

int _main(string[] args) {
    immutable epoch_creator_options = EpochCreatorOptions(800, 5, 5);
    import tagion.services.locator;
    locator_options = new immutable(LocatorOptions)(5, 5.msecs);

    auto epoch_creator_feature = automation!epoch_creator;
    epoch_creator_feature.SendPayloadAndCreateEpoch(epoch_creator_options);
    epoch_creator_feature.run;

    return 0;
}
