#!/usr/bin/env bash
# ADSP 31011 Assignment 2 - every Linux and gcloud command I ran (Parts 1, 2, 5)

# ---- Part 1.2: Cloud Shell and Linux ----
mkdir -p ~/CNDE/Assignment2
cd ~/CNDE/Assignment2
pwd
git init
printf 'env.sh\nsakila-db/\nsakila-db.tar.gz\n.ipynb_checkpoints/\n.virtual_documents/\n.claude/tool-log.txt\n' > .gitignore
cat .gitignore
history | tail -15

# ---- Part 2.0: configuration (the password lives only in env.sh, never on the command line) ----
nano env.sh                      # PROJECT, REGION, INSTANCE, DB, MYSQL_ROOT_PW (later also CONNECTION_NAME, CLOUDSDK_CORE_PROJECT, PATH)
source env.sh                    # load the variables into this shell
echo $PROJECT $INSTANCE $DB      # check the variables (never echo the password)
git status                       # env.sh must NOT appear here (.gitignore works)
gcloud config set project $PROJECT                # point gcloud at my project (the id lives only in env.sh)
gcloud services enable sqladmin.googleapis.com    # turn on the Cloud SQL Admin API

# ---- Part 2.1: create the instance and the database ----
gcloud sql instances create $INSTANCE --database-version=MYSQL_8_0 --edition=ENTERPRISE --tier=db-f1-micro --region=$REGION --root-password="$MYSQL_ROOT_PW"   # password comes from env.sh, not typed here
gcloud sql databases create $DB --instance=$INSTANCE                                                        # the sakila database
gcloud sql instances describe $INSTANCE --format='table(name,databaseVersion,settings.tier,region,state)'  # expect state RUNNABLE

# ---- Part 2.2: download, unpack and import Sakila (schema first, then data) ----
wget https://downloads.mysql.com/docs/sakila-db.tar.gz                    # download the Sakila sample database
tar -xzf sakila-db.tar.gz                                                 # unpack into sakila-db/
ls -la sakila-db                                                          # sakila-schema.sql, sakila-data.sql, sakila.mwb
gcloud sql connect $INSTANCE --user=root < sakila-db/sakila-schema.sql    # create the tables, views, triggers (password typed at the prompt)
gcloud sql connect $INSTANCE --user=root < sakila-db/sakila-data.sql      # load the rows

# ---- Part 2.3: connect and verify ----
# note: the current Sakila download is newer than the brief: 16,044 payments totalling 67,406.56
#       (brief says 16,049 / 67,416.51; instructor confirmed on Canvas to use our own import's numbers)
gcloud sql connect $INSTANCE --user=root    # interactive mysql session, then:
#   USE sakila;
#   SHOW FULL TABLES WHERE Table_type = 'BASE TABLE';                          -> 16 rows
#   SELECT COUNT(*) FROM film;                                                  -> 1000
#   SELECT COUNT(*) AS payments, ROUND(SUM(amount),2) AS total FROM payment;   -> 16044 | 67406.56
#   exit

# ---- Part 2 wrap-up: save progress ----
git status                                                             # only .gitignore and LinuxCommands.sh; env.sh and sakila-db/ are ignored
git add -A && git commit -m "Parts 1-2: setup, Cloud SQL instance, Sakila import"

# ---- Part 5: clean up ----
./deploy_sakila.sh down            # my Part 4 script; I typed the instance name to confirm (made executable earlier with chmod +x)
gcloud sql instances list          # -> Listed 0 items.
rm -r sakila-db sakila-db.tar.gz   # delete the downloaded Sakila files
ls                                 # confirm they are gone


