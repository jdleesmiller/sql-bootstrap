# SQL Bootstrap

## Usage

First generate the example data, then run the calculations.

```sh
make examples
make
```

## Setup Notes

### Local Postgres

```
postgres -D /usr/local/var/postgres
psql
```

### BigQuery

```
gcloud auth list
gcloud config set account ...
gcloud config set project ...
```
