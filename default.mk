#DC?=dmd
export GODEBUG:=cgocheck=0
WOLFSSL?=1
OLD?=1
ONETOOL?=1
DEBUGGER?=ddd
VERBOSE_COMPILER_ERRORS=1

export TEST_STAGE:=commit
export SEED:=$(shell git rev-parse HEAD)

RELEASE_DFLAGS+=$(DOPT)

#DFLAGS+=-s
ifndef DEBUG_DISABLE
DFLAGS+=$(DDEBUG_SYMBOLS)
endif

DFLAGS+=$(DVERSION)=REDBLACKTREE_SAFE_PROBLEM


# Extra DFLAGS for the testbench 
BDDDFLAGS+=$(DDEBUG_SYMBOLS)
BDDDFLAGS+=$(DEXPORT_DYN)

ifdef WOLFSSL
DFLAGS+=$(DVERSION)=TINY_AES
DFLAGS+=$(DVERSION)=WOLFSSL
SSLIMPLEMENTATION=$(LIBWOLFSSL)
else
SSLIMPLEMENTATION=$(LIBOPENSSL)
NO_WOLFSSL=-a -not -path "*/wolfssl/*"
endif

ifdef OLD
DFLAGS+=$(DVERSION)=OLD_TRANSACTION
endif

DFLAGS+=$(DVERSION)=REAL_HASHES

ifdef SECP256K1_HASH
DFLAGS+=$(DVERSION)=SECP256K1_HASH
endif

