export DBUILD := ${abspath ${DROOT}}/build/$(MTRIPLE)

# New simplified flow directories
export DBIN := $(DBUILD)/bin
export DTMP := $(DBUILD)/tmp
export DOBJ := $(DBUILD)/obj
export DLIB := $(DBUILD)/lib

env-dirs:
	$(PRECMD)
	$(call log.header, $@ :: dirs)
	$(call log.kvp, DBUILD, $(DBUILD))
	$(call log.kvp, DBIN, $(DBIN))
	$(call log.kvp, DOBJ, $(DOBJ))
	$(call log.kvp, DTMP, $(DTMP))
	$(call log.kvp, DLIB, $(DLIB))
	$(call log.kvp, DSRC, $(DSRC))
	$(call log.kvp, DTUB, $(DTUB))
	$(call log.kvp, DROOT, $(DROOT))
	$(call log.close)

env: env-dirs
