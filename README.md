# SQL Bootstrap

## Usage

First generate the example data, then run the calculations.

```sh
make example-data
make
```

## Setup Notes

### Local Postgres

```
postgres -D /usr/local/var/postgres
psql
```

### Cloud SQL Postgres

```
make cloud-sql-instance
make cloud-sql-proxy
PSQL="psql postgres://postgres:$CLOUD_SQL_PGPASSWORD@localhost:5432" make pg-test benchmark-pg.csv
```

### BigQuery

```
gcloud config configurations activate ...
gcloud config set project ...
```
