# Recursive run in src/*
on-run:
	@cp $(DIR_TUB)/scripts/run $(DIR_ROOT)/run

off-run:
	@rm $(DIR_ROOT)/run