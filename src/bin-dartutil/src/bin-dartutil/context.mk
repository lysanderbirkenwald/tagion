DEPS += lib-dart
DEPS += lib-crypto

PROGRAM:=tagiondartutil

$(PROGRAM).configure: SOURCE := tagion/*.d

$(DBIN)/$(PROGRAM): $(DTMP)/libsecp256k1.a
$(DBIN)/$(PROGRAM): $(DTMP)/libssl.a
$(DBIN)/$(PROGRAM): $(DTMP)/libcrypto.a
$(DBIN)/$(PROGRAM): $(DTMP)/libp2pgowrapper.a