BQ ?= bq
PSQL ?= psql
R ?= Rscript --vanilla

BQ_DATASET ?= hits

all: examples

# Using "flag" files to track non-file targets
.flags:
	mkdir -p $@

example-data/examples.csv: make-example-data.R
	mkdir -p example-data
	Rscript --vanilla make-example-data.R

HITS_CSVS = $(wildcard example-data/hits-*.csv)

.flags/sql-load: example-data/examples.csv make-sql-load-scripts.R
	Rscript --vanilla make-sql-load-scripts.R | $(PSQL)
	touch $@
sql-load: .flags/sql-load

sql-drop: example-data/examples.csv
	$(R) make-sql-drop-scripts.R | $(PSQL)

.flags/bq-hits:
	$(BQ) mk --force --dataset $(BQ_DATASET)
.flags/bq-hits-%.csv: example-data/hits-%.csv
	$(BQ) rm --force --table $(BQ_DATASET).hits_$*
	$(BQ) load --skip_leading_rows=1 \
	  $(BQ_DATASET).hits_$* $< created_at:timestamp,converted:boolean
	touch $@
bq-load: .flags/bq-hits
bq-load: $(patsubst example-data/hits-%.csv,.flags/bq-hits-%.csv,$(HITS_CSVS))

bq-drop:
	$(BQ) rm --force --recursive $(BQ_DATASET)
	rm -f .flags/bq-hits*

example-sql/bootstrap-pure.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits pure pg > $@

example-sql/bootstrap-poisson.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits poisson pg > $@

example-sql/bq-bootstrap-pure.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits pure bq > $@

example-sql/bq-bootstrap-poisson.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits poisson bq > $@

examples: example-data/examples.csv
examples:	example-sql/bootstrap-pure.sql example-sql/bootstrap-poisson.sql
examples:	example-sql/bq-bootstrap-pure.sql example-sql/bq-bootstrap-poisson.sql

clean: sql-drop
	rm -rf example-data .flags

.PHONY: examples clean sql-load sql-drop bq-load bq-drop
