#!/bin/bash
set -em

function show_help {
  echo "
  ktl pg:diagnose [-lapp=db -ndefault -h]

  Shows diagnostics report for PostgreSQL database.

  Options:
    -lSELECTOR          Selector for a pod that exposes PostgreSQL instance. Default: app=db.
    -nNAMESPACE         Namespace for a pod that exposes PostgreSQL instance. Default: default.
    -h                  Show help and exit.

  Examples:
    ktl pg:diagnose
    ktl pg:diagnose -lapp=db
    ktl pg:diagnose -lapp=db -p5433
"
}

# TODO: add more stats from https://github.com/heroku/heroku-pg-extras

K8S_SELECTOR="app=db"
PORT=$(awk 'BEGIN{srand();print int(rand()*(63000-2000))+2000 }')
POSTGRES_DB="postgres"

# Read configuration from CLI
while getopts "hn:l:p:rn:t" opt; do
  case "$opt" in
    n)  K8S_NAMESPACE="--namespace=${OPTARG}"
        ;;
    l)  K8S_SELECTOR="${OPTARG}"
        ;;
    p)  PORT="${OPTARG}"
        ;;
    h)  show_help
        exit 0
        ;;
  esac
done

set +e
nc -z localhost ${PORT} < /dev/null
if [[ $? == "0" ]]; then
  echo "[E] Port ${PORT} is busy, try to specify different port name with -p option."
  exit 1
fi
set -e

echo " - Selecting pod with '-l ${K8S_SELECTOR} -n ${K8S_NAMESPACE:-default}' selector."
SELECTED_PODS=$(
  kubectl get pods ${K8S_NAMESPACE} \
    -l ${K8S_SELECTOR} \
    -o json \
    --field-selector=status.phase=Running
)
POD_NAME=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.name')

if [ ! ${POD_NAME} ]; then
  echo "[E] Pod wasn't found. Try to select it with -n (namespace) and -l options."
  exit 1
fi

echo " - Found pod ${POD_NAME}."

DB_CONNECTION_SECRET=$(echo ${SELECTED_PODS} | jq -r '.items[0].metadata.labels.connectionSecret')
echo " - Resolving database user and password from secret ${DB_CONNECTION_SECRET}."
DB_SECRET=$(kubectl get secrets ${DB_CONNECTION_SECRET} -o json)
POSTGRES_USER=$(echo "${DB_SECRET}" | jq -r '.data.username' | base64 -D)
POSTGRES_PASSWORD=$(echo "${DB_SECRET}" | jq -r '.data.password' | base64 -D)
POSTGRES_CONNECTION_STRING="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${PORT}/${POSTGRES_DB}"

# Trap exit so we can try to kill proxies that has stuck in background
function cleanup {
  kill $! &> /dev/null
  kill %1 &> /dev/null
}
trap cleanup EXIT

echo " - Port forwarding remote PostgreSQL to localhost port ${PORT}."
kubectl ${K8S_NAMESPACE} port-forward ${POD_NAME} ${PORT}:5432 &> /dev/null &

for i in `seq 1 30`; do
  [[ "${i}" == "30" ]] && echo "Failed waiting for port forward" && exit 1
  nc -z localhost ${PORT} && break
  echo -n .
  sleep 1
done

psql "${POSTGRES_CONNECTION_STRING}" --command "
  WITH table_scans as (
      SELECT relid,
          tables.idx_scan + tables.seq_scan as all_scans,
          ( tables.n_tup_ins + tables.n_tup_upd + tables.n_tup_del ) as writes,
                  pg_relation_size(relid) as table_size
          FROM pg_stat_user_tables as tables
  ),
  all_writes as (
      SELECT sum(writes) as total_writes
      FROM table_scans
  ),
  indexes as (
      SELECT idx_stat.relid, idx_stat.indexrelid,
          idx_stat.schemaname, idx_stat.relname as tablename,
          idx_stat.indexrelname as indexname,
          idx_stat.idx_scan,
          pg_relation_size(idx_stat.indexrelid) as index_bytes,
          indexdef ~* 'USING btree' AS idx_is_btree
      FROM pg_stat_user_indexes as idx_stat
          JOIN pg_index
              USING (indexrelid)
          JOIN pg_indexes as indexes
              ON idx_stat.schemaname = indexes.schemaname
                  AND idx_stat.relname = indexes.tablename
                  AND idx_stat.indexrelname = indexes.indexname
      WHERE pg_index.indisunique = FALSE
  ),
  index_ratios AS (
  SELECT schemaname, tablename, indexname,
      idx_scan, all_scans,
      round(( CASE WHEN all_scans = 0 THEN 0.0::NUMERIC
          ELSE idx_scan::NUMERIC/all_scans * 100 END),2) as index_scan_pct,
      writes,
      round((CASE WHEN writes = 0 THEN idx_scan::NUMERIC ELSE idx_scan::NUMERIC/writes END),2)
          as scans_per_write,
      pg_size_pretty(index_bytes) as index_size,
      pg_size_pretty(table_size) as table_size,
      idx_is_btree, index_bytes
      FROM indexes
      JOIN table_scans
      USING (relid)
  ),
  index_groups AS (
  SELECT 'Never Used Indexes' as reason, *, 1 as grp
  FROM index_ratios
  WHERE
      idx_scan = 0
      and idx_is_btree
  UNION ALL
  SELECT 'Low Scans, High Writes' as reason, *, 2 as grp
  FROM index_ratios
  WHERE
      scans_per_write <= 1
      and index_scan_pct < 10
      and idx_scan > 0
      and writes > 100
      and idx_is_btree
  UNION ALL
  SELECT 'Seldom Used Large Indexes' as reason, *, 3 as grp
  FROM index_ratios
  WHERE
      index_scan_pct < 5
      and scans_per_write > 1
      and idx_scan > 0
      and idx_is_btree
      and index_bytes > 100000000
  UNION ALL
  SELECT 'High-Write Large Non-Btree' as reason, index_ratios.*, 4 as grp
  FROM index_ratios, all_writes
  WHERE
      ( writes::NUMERIC / ( total_writes + 1 ) ) > 0.02
      AND NOT idx_is_btree
      AND index_bytes > 100000000
  ORDER BY grp, index_bytes DESC )
  SELECT reason, schemaname, tablename, indexname,
      index_scan_pct, scans_per_write, index_size, table_size
  FROM index_groups;
"
