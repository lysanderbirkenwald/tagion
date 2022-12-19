
BDD_FLAGS+=-p
BDD_FLAGS+=-i$(BDD)/bdd_import.di
BDD_FLAGS+=${addprefix -I,$(BDD)}


BDD_DFLAGS+=${addprefix -I,$(BDD)}

export BDD_LOG=$(DLOG)/bdd
export BDD_RESULTS=$(BDD_LOG)/results

BDD_DFILES+=${shell find $(BDD) -name "*.d" -a -not -name "*.gen.d" -a -path "*/testbench/*" -a -not -path "*/unitdata/*" $(NO_WOLFSSL) }

#
# Binary testbench 
#
testbench: bddfiles
target-testbench: DFLAGS+=$(DVERSION)=ONETOOL
target-testbench: LIBS+=$(SSLIMPLEMENTATION) $(LIBSECP256K1) $(LIBP2PGOWRAPPER)
target-testbench: DFILES+=$(BDD_DFILES)
#target-testbench: $(BDD_DFILES)

${call DO_BIN,testbench,}

#$(DBIN)/testbench: $(BDD_DFILES) $(DFILES)


