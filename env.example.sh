# Copy to env.sh, fill in, then:  source env.sh      (env.sh is git-ignored - never commit it)
export PROJECT="your-gcp-project-id"
export REGION="us-central1"
export INSTANCE="sakila"
export DB="sakila"
export MYSQL_ROOT_PW="choose-a-long-password"                 # the only place the password lives
export CLOUDSDK_CORE_PROJECT="$PROJECT"                        # gcloud uses this project without `gcloud config set`
export CONNECTION_NAME="$PROJECT:$REGION:$INSTANCE"            # used by cloud-sql-proxy and the Python connector
