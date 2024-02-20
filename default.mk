#DC?=dmd
export GODEBUG:=cgocheck=0
ONETOOL?=1
DEBUGGER?=ddd
VERBOSE_COMPILER_ERRORS=1
# SECP256K1_DEBUG=1

export TEST_STAGE:=commit
export SEED:=$(shell git rev-parse HEAD)

RELEASE_DFLAGS+=$(DOPT)

ifeq (COMPILER, ldc)
RELEASE_DFLAGS+=--allinst
RELEASE_DFLAGS+=--mcpu=native
RELEASE_DFLAGS+=--flto=thin
RELEASE_DFLAGS+=--defaultlib=phobos2-ldc-lto,druntime-ldc-lto
endif

# USE_SYSTEM_LIBS=1 # Compile with system libraries (nng & secp256k1-zkp)

# If youre using system libraries they'll most likely be compiled with mbedtls support
# So mbedtls needs to be linked as well, so this need to be enabled
# NNG_ENABLE_TLS=1

ifndef DEBUG_DISABLE
DFLAGS+=$(DDEBUG_SYMBOLS)
endif

DFLAGS+=$(DWARN)

# Uses a modified version of phobos' redblacktree
# So it's more compatiblae with @safe code
DFLAGS+=$(DVERSION)=REDBLACKTREE_SAFE_PROBLEM

# This fixes an error in the app wallet where it would be logged out after each operation
# By copying the securenet each time an operation is done
DFLAGS+=$(DVERSION)=NET_HACK

# Sets the inputvalidators NNG socket to be blocking
DFLAGS+=$(DVERSION)=BLOCKING

# Fix a randomly occuring RangeError on hashgraph startup
# By filtering out empty events
DFLAGS+=$(DVERSION)=EPOCH_FIX

# This allows an experimental nft function to be used without payment
# The function is not used in this node
DFLAGS+=$(DVERSION)=WITHOUT_PAYMENT

# Enables the new wallet update request proposed in 
# https://docs.tagion.org/#/documents/TIPs/cache_proposal_23_jan
DFLAGS+=$(DVERSION)=TRT_READ_REQ

# Use compile time sorted, serialization of dart branches
DFLAGS+=$(DVERSION)=DARTFile_BRANCHES_SERIALIZER

# Dart optimization that inserts segments sorted.
# Before it would sort the segments every time they were needed
DFLAGS+=$(DVERSION)=WITHOUT_SORTING

# Always use the Genesis epoch to determine the boot nodes
# There is currently no way to function to determine the nodes from latest epoch
DFLAGS+=$(DVERSION)=USE_GENESIS_EPOCH

# # This enables a redundant check in dart to see if there are overlaps between segments 
# DFLAGS+=$(DVERSION)=DART_RECYCLER_INVARINAT

# # This is used for the wallet wrapper to generate pseudo random history
# # which is useful for app development
# DFLAGS+=$(DVERSION)=WALLET_HISTORY_DUMMY


#DFLAGS+=$(DVERSION)=TOHIBON_SERIALIZE_CHECK
# Extra DFLAGS for the testbench 
BDDDFLAGS+=$(DDEBUG_SYMBOLS)
BDDDFLAGS+=$(DEXPORT_DYN)

INSTALL?=$(HOME)/bin
