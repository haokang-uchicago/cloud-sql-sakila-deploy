#!/usr/bin/env bash
# deploy_sakila.sh - Cloud SQL (MySQL 8.0) + Sakila, end to end, safe to re-run
#   ./deploy_sakila.sh        create instance + db, download, import, verify (skips what is already done)
#   ./deploy_sakila.sh down   delete the instance (asks first)
set -euo pipefail

cd "$(dirname "$0")"
source ./env.sh                                   # REGION, INSTANCE, DB, CONNECTION_NAME, MYSQL_ROOT_PW, CLOUDSDK_CORE_PROJECT (never echoed)
: "${REGION:?set in env.sh}" "${INSTANCE:?set in env.sh}" "${DB:?set in env.sh}" "${CONNECTION_NAME:?set in env.sh}" "${MYSQL_ROOT_PW:?set in env.sh}"

SAKILA_URL=https://downloads.mysql.com/docs/sakila-db.tar.gz
SAKILA_TGZ=sakila-db.tar.gz
SAKILA_DIR=sakila-db
PROXY_PORT=3307

instance_exists() { gcloud sql instances describe "$INSTANCE" >/dev/null 2>&1; }

# ---- teardown ----
if [[ "${1:-up}" == "down" ]]; then
  if ! instance_exists; then
    echo "Instance $INSTANCE does not exist - nothing to tear down."
    exit 0
  fi
  read -r -p "Delete Cloud SQL instance '$INSTANCE' and ALL its data? Type the instance name to confirm: " answer
  [[ "$answer" == "$INSTANCE" ]] || { echo "Aborted - nothing deleted."; exit 1; }
  gcloud sql instances delete "$INSTANCE" --quiet
  echo "Instance $INSTANCE deleted."
  exit 0
elif [[ "${1:-up}" != "up" ]]; then
  echo "usage: $0 [up|down]" >&2
  exit 2
fi

# ---- Part 2.0: API (project comes from CLOUDSDK_CORE_PROJECT in env.sh) ----
gcloud services enable sqladmin.googleapis.com

# ---- Part 2.1: instance and database (skip if present) ----
if instance_exists; then
  echo "Instance $INSTANCE already exists - skipping create."
else
  gcloud sql instances create "$INSTANCE" --database-version=MYSQL_8_0 --edition=ENTERPRISE \
    --tier=db-f1-micro --region="$REGION" --root-password="$MYSQL_ROOT_PW"
fi
gcloud sql instances describe "$INSTANCE" --format='table(name,databaseVersion,settings.tier,region,state)'

if gcloud sql databases describe "$DB" --instance="$INSTANCE" >/dev/null 2>&1; then
  echo "Database $DB already exists - skipping create."
else
  gcloud sql databases create "$DB" --instance="$INSTANCE"
fi

# ---- Part 2.2a: download and unpack only if missing ----
if [[ ! -f "$SAKILA_DIR/sakila-schema.sql" || ! -f "$SAKILA_DIR/sakila-data.sql" ]]; then
  [[ -f "$SAKILA_TGZ" ]] || wget -q -O "$SAKILA_TGZ" "$SAKILA_URL"
  tar -xzf "$SAKILA_TGZ"
fi

# ---- connect without a password prompt: Cloud SQL Auth Proxy + a private mysql defaults file ----
WORK=$(mktemp -d)
PROXY_PID=""
cleanup() { [[ -n "$PROXY_PID" ]] && kill "$PROXY_PID" 2>/dev/null || true; rm -f "$WORK"/my.cnf "$WORK"/proxy.log; rmdir "$WORK" 2>/dev/null || true; }
trap cleanup EXIT

cloud-sql-proxy --gcloud-auth --address 127.0.0.1 --port "$PROXY_PORT" "$CONNECTION_NAME" >"$WORK/proxy.log" 2>&1 &
PROXY_PID=$!

( umask 077; printf '[client]\nuser=root\npassword="%s"\nhost=127.0.0.1\nport=%s\n' "$MYSQL_ROOT_PW" "$PROXY_PORT" > "$WORK/my.cnf" )
sql() { mysql --defaults-extra-file="$WORK/my.cnf" "$@"; }
q()   { sql -N -B -e "$1"; }                      # one value, no headers

for _ in $(seq 30); do q "SELECT 1" >/dev/null 2>&1 && break; sleep 1; done
q "SELECT 1" >/dev/null || { echo "Proxy did not come up:"; cat "$WORK/proxy.log"; exit 1; }

# ---- Part 2.2b: import only if Sakila is not already fully loaded ----
base_tables() { q "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$DB' AND table_type='BASE TABLE'"; }
tables=$(base_tables); films=0; payments=0
if [[ "$tables" -eq 16 ]]; then
  films=$(q "SELECT COUNT(*) FROM \`$DB\`.film")
  payments=$(q "SELECT COUNT(*) FROM \`$DB\`.payment")
fi
if [[ "$tables" -eq 16 && "$films" -eq 1000 && "$payments" -eq 16044 ]]; then
  echo "Sakila already loaded in $DB - skipping import."
else
  echo "Importing Sakila (found $tables base tables, $films films, $payments payments) ..."
  sql < "$SAKILA_DIR/sakila-schema.sql"           # drops and recreates the sakila schema, tables, views, triggers
  sql < "$SAKILA_DIR/sakila-data.sql"             # loads the rows
fi

# ---- Part 2.3: verify against known numbers ----
tables=$(base_tables)
films=$(q "SELECT COUNT(*) FROM \`$DB\`.film")
total=$(q "SELECT ROUND(SUM(amount),2) FROM \`$DB\`.payment")

ok=1
check() { if [[ "$2" == "$3" ]]; then echo "PASS  $1 = $2"; else echo "FAIL  $1 = $2 (expected $3)"; ok=0; fi; }
check "base tables  " "$tables" 16
check "film rows    " "$films" 1000
check "payment total" "$total" 67406.56
[[ $ok -eq 1 ]] || { echo "Verification failed - re-import, do not patch rows."; exit 1; }
echo "Sakila verified on $INSTANCE/$DB."
