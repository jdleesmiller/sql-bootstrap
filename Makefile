R ?= Rscript --vanilla
PSQL ?= psql

all: examples

# Using "flag" files to track non-file targets
.flags:
	mkdir -p $@

example-data/examples.csv: make-example-data.R
	mkdir -p example-data
	Rscript --vanilla make-example-data.R

.flags/sql-load: example-data/examples.csv make-sql-load-scripts.R
	Rscript --vanilla make-sql-load-scripts.R | $(PSQL)
	touch $@
sql-load: .flags/sql-load

sql-drop: example-data/examples.csv
	$(R) make-sql-drop-scripts.R | $(PSQL)

example-sql/bootstrap-pure.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits pure > $@

example-sql/bootstrap-poisson.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits poisson > $@

examples: example-data/examples.csv
examples:	example-sql/bootstrap-pure.sql example-sql/bootstrap-poisson.sql

clean: sql-drop
	rm -rf example-data .flags

.PHONY: examples clean sql-load sql-drop
