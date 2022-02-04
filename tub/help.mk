HELPER+=main_help

.PHONY: help

help: help-main

TUB_COMMIT = ${shell cd $(DROOT)/tub; git rev-parse --short HEAD}
TUB_BRANCH = ${shell cd $(DROOT)/tub; git rev-parse --abbrev-ref HEAD}

help-main:
	$(PRECMD)
	${call log.header, $@ :: help}
	${call log.help, "make help-main", "Will display this part"}
	${call log.help, "make help", "Show all helps"}
	${call log.line}
	${call log.help, "make init", "First-time tub initialization (required)"}
	${call log.line}
	${call log.help, "make clean", "Cleans the generated files from the prime source"}
	${call log.line}
	${call log.help, "make prober-all", "Cleans all"}
	${call log.help, "make prober", "Cleans the current platform"}
	${call log.line}
	${call log.help, "make prebuild", "Executes the prebuild"}
	${call log.line}
	${call log.help, "make env", "Show Make environment"}
	${call log.line}
	${call log.kvp, "README", "$(DTUB)/README.md"}
	${call log.kvp, "Branch", "$(TUB_BRANCH)"}
	${call log.kvp, "Commit", "$(TUB_COMMIT)"}
	${call log.line}

#	echo "make clone-* BRANCH=<branch>: Clone specific unit"
