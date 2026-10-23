# CLAUDE.md — ADSP 31011 Assignment 2: Sakila on Cloud SQL (MySQL 8.0)

## What this folder is
CNDE/Assignment2 in Cloud Shell: a MySQL 8.0 instance on Google Cloud SQL holding Sakila, MySQL's sample
DVD-rental database, loaded and queried from the command line and from a Jupyter notebook.
- LinuxCommands.sh — every Linux and gcloud command the student actually ran (Parts 1, 2, 5). Read it before writing any script.
- sakila_notebook.ipynb — the Part 3 queries; Part 4 queries are added here.
- sakila-db/ — the downloaded sakila-schema.sql and sakila-data.sql (git-ignored).

## Facts the agent must not guess
- Configuration lives in env.sh (git-ignored) and is read as environment variables:
  PROJECT, REGION, INSTANCE, DB, MYSQL_ROOT_PW, plus CONNECTION_NAME, CLOUDSDK_CORE_PROJECT and PATH,
  so `source env.sh` is all a script needs (no separate `gcloud config set project` or CONNECTION_NAME lookup).
  Never read env.sh, never print the password, never write any of these values into a file or a prompt.
- Instance: MYSQL_8_0, edition ENTERPRISE, tier db-f1-micro, region us-central1. Database: sakila.
- Data source: https://downloads.mysql.com/docs/sakila-db.tar.gz → sakila-db/sakila-schema.sql, then sakila-db/sakila-data.sql.
  Import order matters: schema first, then data.
- Expected counts from our own import:
  16 base tables (plus 7 views) · film 1,000 · payment 16,044 rows totalling 67,406.56.
  The brief says 16,049 payments / 67,416.51 — that was an older Sakila; the instructor confirmed 67,406.56 for the current download.
  A mismatch means re-import, never "fix" rows.

## How to work here
- Read this file and LinuxCommands.sh before proposing anything.
- Show the plan, then the diff. Run nothing before the student approves it.
- Never run gcloud commands that create, change or delete resources (instances, databases, imports, teardown) — the student runs those.
- Scripts: bash, `set -euo pipefail`, variables read from env.sh at the top, idempotent (safe to re-run; skip create when the resource already exists).
- Verification is a number compared with the expected values above — not "it ran".
- Every SQL answer comes with a check query the student can run.
- prompts.md belongs to the student: you may draft entries; the student edits them.

## Controls in this folder
- .claude/settings.json (copied from the Week 2 kit): allow list (read, python3, gcloud describe/list/connect, git),
  deny list (instance delete, storage rm, rm -rf, reading env.sh), and PreToolUse hooks that log every Bash/Edit/Write to .claude/tool-log.txt.

## Part 4 tasks
1. deploy_sakila.sh — built from LinuxCommands.sh: source env.sh, set -euo pipefail, idempotent create,
   download + unpack + import Sakila, print the three verification counts, and `./deploy_sakila.sh down` for teardown.
2. One hard query: top 5 customers by total payments with the city of their store
   (customer → payment; customer → store → address → city), plus a check query proving the total over all customers equals 67,406.56.