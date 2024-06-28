
include ${call dir.resolve, dstep.mk}


DFILES_NATIVESECP256K1=${shell find $(DSRC)/lib-crypto -name "*.d"}

env-crypto:
	$(PRECMD)
	$(call log.header, $@ :: env)
	$(call log.kvp, LCRYPTO_ROOT,$(LCRYPTO_ROOT))
	$(call log.kvp, LCRYPTO_PACKAGE,$(LCRYPTO_PACKAGE))
	$(call log.close)

.PHONY: env-crypto

env: env-crypto

files-crypto:
	$(PRECMD)
	$(call log.header, $@ :: env)
	$(call log.env, CRYPTO_DFILES,$(CRYPTO_DFILES))
	$(call log.close)

.PHONY: files-crypto

env-files: files-crypto

help-crypto:
	$(PRECMD)
	$(call log.header, $@ :: help)
	$(call log.help, "make env-dstep-$(LCRYPTO_PACKAGE)", "Display secp256k1 dstep env")
	$(call log.close)

help: help-crypto

.PHONY: help-crypto

