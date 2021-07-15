BQ ?= bq
PSQL ?= psql
R ?= Rscript --vanilla

GCP_REGION ?= europe-west2
CLOUD_SQL_PROJECT ?= sql-bootstrap
CLOUD_SQL_INSTANCE ?= sql-bootstrap-1

PSQL_SCHEMA ?= sql_bootstrap
BQ_DATASET ?= sql_bootstrap

BENCHMARK_TRIALS ?= 10

all: examples

# Using "flag" files to track non-file targets
.flags:
	mkdir -p $@

example-data/examples.csv: make-example-data.R
	mkdir -p example-data
	Rscript --vanilla make-example-data.R
example-data: example-data/examples.csv

HITS_CSVS = $(wildcard example-data/hits-*.csv)

.flags/pg-schema:
	$(PSQL) --command 'CREATE SCHEMA IF NOT EXISTS $(PSQL_SCHEMA)'
	touch $@
.flags/pg-hits-%.csv: example-data/hits-%.csv
	$(PSQL) --command 'DROP TABLE IF EXISTS $(PSQL_SCHEMA).hits_$*'
	$(PSQL) --command "CREATE TABLE $(PSQL_SCHEMA).hits_$* \
	  (created_at TIMESTAMP NOT NULL, converted DOUBLE PRECISION NOT NULL)"
	$(PSQL) --command '\COPY $(PSQL_SCHEMA).hits_$* FROM $< WITH CSV HEADER'
	touch $@
pg-load: .flags/pg-schema
pg-load: $(patsubst example-data/hits-%.csv,.flags/pg-hits-%.csv,$(HITS_CSVS))

pg-drop:
	$(PSQL) --command 'DROP SCHEMA IF EXISTS $(PSQL_SCHEMA) CASCADE'
	rm -f .flags/pg-*

pg-test: pg-load
	$(R) make-sql-bootstrap.R 1000 hits_1 poisson pg $(PSQL_SCHEMA) | $(PSQL)

.flags/bq-dataset:
	$(BQ) mk --force --data_location=$(GCP_REGION) --dataset $(BQ_DATASET)
	touch $@
.flags/bq-hits-%.csv: example-data/hits-%.csv
	$(BQ) rm --force --table $(BQ_DATASET).hits_$*
	$(BQ) load --skip_leading_rows=1 \
	  $(BQ_DATASET).hits_$* $< created_at:timestamp,converted:float64
	touch $@
bq-load: .flags/bq-dataset
bq-load: $(patsubst example-data/hits-%.csv,.flags/bq-hits-%.csv,$(HITS_CSVS))

bq-drop:
	$(BQ) rm --force --recursive $(BQ_DATASET)
	rm -f .flags/bq-*

bq-test:
	$(R) make-sql-bootstrap.R 1000 hits_1 poisson bq $(BQ_DATASET) | \
		$(BQ) --location=$(GCP_REGION) query --use_legacy_sql=false

benchmark-pg.csv: benchmark.R pg-load
	$(R) $< $@ pg $(BENCHMARK_TRIALS) $(PSQL)

benchmark-bq.csv: benchmark.R bq-load
	$(R) $< $@ bq $(BENCHMARK_TRIALS) \
	  $(BQ) --location=$(GCP_REGION) query --use_legacy_sql=false

benchmark: benchmark-pg.csv benchmark-bq.csv

# Please don't delete all my results on Ctrl-C...
.PRECIOUS: benchmark-pg.csv benchmark-bq.csv

check.csv: check.R example-data
	$(R) $< $@

example-sql/bootstrap-pure.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits pure pg none > $@

example-sql/bootstrap-poisson.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits poisson pg none > $@

example-sql/bq-bootstrap-pure.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits pure bq $(BQ_DATASET) > $@

example-sql/bq-bootstrap-poisson.sql: make-sql-bootstrap.R
	$(R) $< 1000 hits poisson bq $(BQ_DATASET) > $@

examples:	example-sql/bootstrap-pure.sql example-sql/bootstrap-poisson.sql
examples:	example-sql/bq-bootstrap-pure.sql example-sql/bq-bootstrap-poisson.sql

doc/cats-example.svg: doc/cats-example.R
	$(R) $<
doc: doc/cats-example.svg

cloud-sql-instance:
	@test -n "$(CLOUD_SQL_PGPASSWORD)"
	gcloud sql instances create $(CLOUD_SQL_INSTANCE) --cpu=4 --memory=16384MB \
		--database-version=POSTGRES_13 --region=$(GCP_REGION)
	@gcloud sql users set-password postgres --instance=$(CLOUD_SQL_INSTANCE) \
		--password="$(CLOUD_SQL_PGPASSWORD)"
	gcloud sql instances patch $(CLOUD_SQL_INSTANCE) \
	  --database-flags temp_file_limit=335544320

bin/cloud_sql_proxy: ARCH ?= $(shell uname | tr '[:upper:]' '[:lower:]')
bin/cloud_sql_proxy:
	mkdir -p bin
	curl -o $@ https://dl.google.com/cloudsql/cloud_sql_proxy.$(ARCH).amd64
	chmod +x $@

cloud-sql-proxy: bin/cloud_sql_proxy
	$< -instances=$(CLOUD_SQL_PROJECT):$(GCP_REGION):$(CLOUD_SQL_INSTANCE)=tcp:5432

clean: pg-drop bq-drop
	rm -rf example-data .flags
	rm -f docs/*.svg

test: pg-test bq-test

.PHONY: doc examples example-data clean test
.PHONY: sql-load sql-drop sql-test
.PHONY: bq-load bq-drop bq-test
.PHONY: cloud-sql-instance cloud-sql-proxy
