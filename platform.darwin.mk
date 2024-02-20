
#
# Darwin
#
DARWIN_arm64:=arm64-darwin
PLATFORMS+=$(DARWIN_arm64)

ifeq ($(PLATFORM),$(DARWIN_arm64))
DINC+=${shell find $(DSRC) -maxdepth 1 -type d -path "*src/lib-*" }

$(UNITTEST_BIN): $(DFILES)

unittest: proto-unittest-run

build-unittest: proto-unittest-build

endif
