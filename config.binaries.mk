export GODEBUG=cgocheck=0


#
# Targets for all binaries
#

#
# Core program
#
target-tagionwave: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-wave/*" -a -not -path "*/unitdata/*" }
${call BIN,tagionwave,TAGIONWAVE,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER),$(ONETOOL)}

#
# HiBON utility
#
# FIXME(CBR) should be remove when ddeps works correctly
target-hibonutil: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-hibonutil/*" -a -not -path "*/unitdata/*" }
${call BIN,hibonutil,HIBONUTIL,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER),$(ONETOOL)}


#
# DART utility
#
# FIXME(CBR) should be remove when ddeps works correctly
target-dartutil: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-dartutil/*" -a -not -path "*/unitdata/*" }
${call BIN,dartutil,DARTUTIL,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER),$(ONETOOL)}

#
# WASM utility
#
# FIXME(CBR) should be remove when ddeps works correctly
target-wasmutil: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-wasmutil/*" -a -not -path "*/unitdata/*" }
${call BIN,wasmutil,WASMUTIL,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)}

#
# WASM utility
#
# FIXME(CBR) should be remove when ddeps works correctly
target-tagionwallet: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-wallet/*" -a -not -path "*/unitdata/*" }
${call BIN,tagionwallet,TAGIONWALLET,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER),$(ONETOOL)}

wallet: target-tagionwallet
#
# Logservicetest utility
#
# FIXME(IB) should be removed when ddeps works correctly
target-tagionlogservicetest: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-logservicetest/*" -a -not -path "*/unitdata/*" }
${call BIN,tagionlogservicetest,LOGSERVICETEST,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)}

#
# Subscription utility
#
# FIXME(IB) should be removed when ddeps works correctly
target-tagionsubscription: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-subscription/*" -a -not -path "*/unitdata/*" }
${call BIN,tagionsubscription,SUBSCRIPTION,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)}

#
# Recorderchain utility
#
target-recorderchain: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-recorderchain/*" -a -not -path "*/unitdata/*" }
${call BIN,recorderchain,RECORDERCHAIN,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)}

#
# Boot utility
#
# fixme(cbr): When ddeps.mk work those libs are not needed
target-tagionboot: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-boot/*" -a -not -path "*/unitdata/*" -a -not -path "*/lib-betterc/*"}
${call BIN,tagionboot,TAGIONBOOT,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER),$(ONETOOL)}

target-tagion: DFLAGS+=$(DVERSION)=TAGION_TOOLS
target-tagion: DFILES:=${shell find $(DSRC) -name "*.d" -a -path "*/src/lib-*" -a -not -path "*/unitdata/*" -a -not -path "*/tests/*" -a -not -path "*/lib-betterc/*"}
target-tagion: DFILES+=${shell find $(DSRC)/bin-wave/tagion -name "*.d"  }
target-tagion: DFILES+=${shell find $(DSRC)/bin-dartutil/tagion -name "*.d"  }
target-tagion: DFILES+=${shell find $(DSRC)/bin-hibonutil/tagion -name "*.d"  }
target-tagion: DFILES+=${shell find $(DSRC)/bin-wallet/tagion -name "*.d"  }
target-tagion: DFILES+=${shell find $(DSRC)/bin-tools/tagion -name "*.d"  }
target-tagion: DFILES+=${shell find $(DSRC)/bin-boot/tagion -name "*.d"  }
# target-tagion: DFILES+=${shell find $(DSRC)/bin-dartutil -name "*.d" -a -not -path "*/unitdata/*" }
# target-tagion: DFILES+=${shell find $(DSRC)/bin-hibonutil -name "*.d" -a -not -path "*/unitdata/*" }
# target-tagion: DFILES+=${shell find $(DSRC)/bin-wallet -name "*.d" -a -not -path "*/unitdata/*" }

target-tagion:
${call BIN,tagion,TAGION,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)}

# tagion-info:
# 	@echo $(DFILES)

#
# Binary of BBD
#
target-behaviour: DFILES+=${shell find $(DSRC) -name "*.d" -a -path "*/src/bin-behaviour/*" -a -not -path "*/unitdata/*" }
${call BIN,behaviour,BEHAVIOUR,$(LIBOPENSSL) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)}
