# prompts.md — Assignment 2, Part 4
(Owned by the student. Claude drafted the first entry; I rewrote it from what actually happened.)

## Prompt 1 — Claude Code → deploy_sakila.sh (Part 4.1)
**Prompt (plan mode):**
> Read CLAUDE.md and LinuxCommands.sh. Write deploy_sakila.sh: variables at the top read from env.sh (source it), set -euo pipefail, idempotent (skip create when the instance already exists, and skip the import when Sakila is already loaded), download and unpack Sakila only if it is missing, import sakila-schema.sql then sakila-data.sql, print the three verification counts (16 base tables, film 1,000, payment total 67,406.56), and support ./deploy_sakila.sh down for teardown. Do not run anything. Show me the plan and the diff first.

**What came back:** a plan and diff for a 100-line deploy_sakila.sh — source env.sh; skip create when the instance or database exists; download/unpack only if missing; connect without a password prompt through cloud-sql-proxy and a temporary chmod-600 mysql option file that a `trap` deletes on exit; skip the import only when 16 tables / 1,000 films / 16,044 payments already match; PASS/FAIL against 16 / 1000 / 67406.56; `down` makes me type the instance name before it deletes anything.

**What was wrong:**
1. Claude pointed out that my CLAUDE.md was still the Week 2 ClassicModels version — I had copied it but not edited it yet.
2. CLAUDE.md says "run nothing before the student approves it", but the hook log (.claude/tool-log.txt) shows Claude ran `bash -n deploy_sakila.sh && echo SYNTAX_OK; ls prompts.md` without asking. Both are allowed by `Bash(bash -n *)` and `Bash(ls *)` in .claude/settings.json. They are read-only, but the allow list overrode the written rule.

**Follow-up prompt (option 3, "Tell Claude what to change"):**
> I have replaced CLAUDE.md with the Sakila version. Re-read it and check the plan still follows it; keep the plan otherwise.

**What came back:** Claude re-read CLAUDE.md and dropped `gcloud config set project`, because env.sh already sets CLOUDSDK_CORE_PROJECT and CONNECTION_NAME. Caveats it raised itself: `--root-password` still puts the password on the gcloud command line during create (the same as my Part 2.1), and a password containing " or \ would need escaping in the option file.

**Diff review (4.1b) — the three things:**
- No password in the file: `grep -cF -- "$MYSQL_ROOT_PW" deploy_sakila.sh` → 0; only the variable name `$MYSQL_ROOT_PW` appears.
- `set -euo pipefail` present: line 5.
- Create is skipped when the instance exists: line 39 ("Instance $INSTANCE already exists - skipping create"), and line 47 does the same for the database.

**What I changed:** replaced CLAUDE.md with the Sakila version and had Claude re-read it; approved the plan with "manually approve edits" (not auto mode); approved each file write one at a time.

**Verification:** `bash -n deploy_sakila.sh` → no errors. Then `chmod +x deploy_sakila.sh` and `./deploy_sakila.sh` against the existing instance:
"Instance sakila already exists - skipping create." · "Database sakila already exists - skipping create." · "Sakila already loaded in sakila - skipping import." · PASS base tables = 16 · PASS film rows = 1000 · PASS payment total = 67406.56 — with no password prompt.

## Prompt 2 — Claude Cowork → sakila_dictionary.md (Part 4.2)
**Prompt:**
> Read sakila-schema.sql in this folder and write sakila_dictionary.md, a data dictionary for a new analyst. For every base table (not the views): its primary key, its foreign keys (column → referenced table.column), and one line on what a row means. Then explain the five relationships a new analyst must know: film–inventory–rental–payment, customer–store–staff, film–actor, film–category, address–city–country. For each relationship, cite the CREATE TABLE statement(s) and the FOREIGN KEY constraint names it comes from.

**What came back:** sakila_dictionary.md — all 16 base tables with primary keys, foreign keys (with constraint names) and one line per row,
plus the five relationships, each citing the CREATE TABLE line and the FOREIGN KEY constraint. The line numbers it cites match sakila-schema.sql.

**Two claims I checked against sakila-schema.sql (4.2b):**
1. "Every table has a last_update audit timestamp." — `sed -n '199,205p' sakila-db/sakila-schema.sql` shows `CREATE TABLE film_text`
   with only film_id, title and description; `grep -c "last_update TIMESTAMP" sakila-db/sakila-schema.sql` → 15, but there are 16 base tables. **Wrong.**
2. "payment.rental_id is nullable (fk_payment_rental, ON DELETE SET NULL)." — `sed -n '269,282p' sakila-db/sakila-schema.sql` shows
   `rental_id INT DEFAULT NULL` and `CONSTRAINT fk_payment_rental FOREIGN KEY (rental_id) REFERENCES rental (rental_id) ON DELETE SET NULL`. **Correct.**

**Which one was wrong or too confident:** claim 1 is wrong — Cowork over-generalised; film_text has no last_update column.
**What I changed:** nothing in the dictionary; I recorded the error here.

## Prompt 3 — Claude Code → top 5 customers by payments + check query (Part 4.3)
**Prompt:**
> For the sakila database: write one SQL query for the top 5 customers by total payments, with the city of their store (customer → payment; customer → store → address → city). Then write a check query proving the total over all customers equals 67,406.56. Explain each join in one line. Do not run anything — give me the two queries and I will run them in my notebook.

**What came back:** two queries, with a one-line explanation of each join; Claude did not run them and said it would not guess names or amounts without running.
Query 1 joins customer → payment (customer_id), customer → store (store_id), store → address (the store's address_id) and address → city,
groups by customer, orders by total paid with customer_id as a tie-breaker, LIMIT 5. Query 2 uses the same joins without LIMIT,
sums every customer's total and compares it with SUM(amount) taken straight from payment.

**What was wrong:** nothing in the SQL. I checked the one easy mistake: the city comes from the store's address (`a.address_id = s.address_id`),
not the customer's own address (`c.address_id`). My own error: I first put the new cells after `conn.close()`, so running a cell gave
InterfaceError (0, '') — connection closed.

**What I changed:** dropped `USE sakila;` and the trailing semicolons so each query runs through the notebook's `q()` helper;
moved `conn.close()` back to the last cell; then Restart Kernel and Run All Cells.

**Result in the notebook:** top 5 — KARL SEAL (store 2, Woodridge) 221.55 · ELEANOR HUNT (store 1, Lethbridge) 216.54 ·
CLARA SHAW (store 1, Lethbridge) 195.58 · RHONDA KENNEDY (store 2, Woodridge) 194.61 · MARION SNYDER (store 2, Woodridge) 194.61
(4th and 5th tie at 194.61; the customer_id tie-breaker fixes their order).
Check: 599 customers, sum over customers = 67406.56 = payment table total. **Reconciles.**