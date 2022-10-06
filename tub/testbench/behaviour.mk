

bdd: bddfiles

.PHONY: bdd

bddfiles: behaviour
	$(PRECMD)
	echo $(BEHAVIOUR) $(BDD_FLAGS)
	$(BEHAVIOUR) $(BDD_FLAGS)

#echo $(DINC)

env-bdd:
	$(PRECMD)
	${call log.header, $@ :: env}
	${call log.env, BDD_FLAGS, $(BDD_FLAGS)}
	${call log.close}

.PHONY: env-bdd

env: env-bdd

help-bdd:
	$(PRECMD)
	${call log.header, $@ :: help}
	${call log.help, "make help-bdd", "Will display this part"}
	${call log.help, "make bdd", "Builds and executes all BDD's"}
	${call log.help, "make bddreport", "Produce visualization of the BDD-reports"}
	${call log.help, "make bddfiles", "Generated the bdd files"}
	${call log.help, "make behaviour", "Builds the BDD tool"}
	${call log.close}

.PHONY: help-bdd

help: help-bdd
