#!/bin/bash
# Copyright 2025 CardinalHQ, Inc
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# Lakerunner Install Script
# This script installs Lakerunner with local MinIO and PostgreSQL

set -e

# Helm Chart Versions
LAKERUNNER_VERSION="0.9.1"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Helper function to conditionally redirect output based on verbose flag
output_redirect() {
    if [ "$VERBOSE" = true ]; then
        cat  # Show output when verbose
    else
        cat >/dev/null 2>&1  # Hide output when not verbose
    fi
}

check_prerequisites() {
    print_status "Checking prerequisites..."

    local missing_deps=()

    if ! command_exists kubectl; then
        missing_deps+=("kubectl")
    fi

    if ! command_exists helm; then
        missing_deps+=("helm")
    fi

    if ! command_exists base64; then
        missing_deps+=("base64")
    fi

    if ! command_exists curl; then
        missing_deps+=("curl")
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies and try again."
        echo "Installation guides:"
        echo "  - kubectl: https://kubernetes.io/docs/tasks/tools/"
        echo "  - helm: https://helm.sh/docs/intro/install/"
        echo "  - curl: Usually pre-installed on most systems"
        exit 1
    fi

    if ! kubectl cluster-info >/dev/null 2>&1; then
        print_error "Cannot connect to Kubernetes cluster. Please ensure:"
        echo "  1. You have a Kubernetes cluster running (minikube, kind, etc.)"
        echo "  2. kubectl is configured to connect to your cluster"
        echo "  3. You have the necessary permissions"
        exit 1
    fi

    print_success "All prerequisites are satisfied"
}

check_helm_repositories() {
    if [ "$SKIP_HELM_REPO_UPDATES" != true ]; then
        return 0  # Skip this check if we're going to add/update repos anyway
    fi

    print_status "Pre-flight check: Verifying required helm repositories..."

    local missing_repos=()
    local found_repos=()
    local needed_repos=()

    # Determine which repositories we need based on configuration
    if [ "$INSTALL_MINIO" = true ]; then
        needed_repos+=("minio https://charts.min.io/")
    fi

    if [ "$INSTALL_POSTGRES" = true ] || [ "$INSTALL_KAFKA" = true ]; then
        needed_repos+=("bitnami https://charts.bitnami.com/bitnami")
    fi

    if [ "$INSTALL_OTEL_DEMO" = true ]; then
        needed_repos+=("open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts")
    fi

    # If no repositories are needed, skip the check
    if [ ${#needed_repos[@]} -eq 0 ]; then
        print_status "No helm repositories required for current configuration"
        return 0
    fi

    # Check each needed repository
    for repo_info in "${needed_repos[@]}"; do
        repo_name=$(echo "$repo_info" | cut -d' ' -f1)
        repo_url=$(echo "$repo_info" | cut -d' ' -f2)

        if helm repo list 2>/dev/null | grep -q "$repo_name.*$repo_url"; then
            found_repos+=("$repo_name")
        else
            missing_repos+=("$repo_info")
        fi
    done

    # Report found repositories
    if [ ${#found_repos[@]} -gt 0 ]; then
        print_success "Found required helm repositories: ${found_repos[*]}"
    fi

    # Report missing repositories and fail if any are missing
    if [ ${#missing_repos[@]} -gt 0 ]; then
        print_error "Missing required helm repositories when --skip-helm-repo-updates is enabled:"
        for repo in "${missing_repos[@]}"; do
            repo_name=$(echo "$repo" | cut -d' ' -f1)
            repo_url=$(echo "$repo" | cut -d' ' -f2)
            echo "  helm repo add $repo_name $repo_url"
        done
        echo
        print_error "Please add the missing repositories and try again, or run without --skip-helm-repo-updates"
        exit 1
    fi

    print_success "All required helm repositories are available"
}

get_input() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"

    if [ -n "$default" ]; then
        read -p "$prompt [$default]: " input
        if [ -z "$input" ]; then
            input="$default"
        fi
    else
        read -p "$prompt: " input
    fi

    eval "$var_name=\"$input\""
}

get_namespace() {
    local default_namespace="lakerunner"

    echo
    echo "=== Namespace Configuration ==="
    echo "Lakerunner will be installed in a Kubernetes namespace."

    get_input "Enter namespace for Lakerunner installation" "$default_namespace" "NAMESPACE"
}

get_infrastructure_preferences() {
    echo
    echo "=== Infrastructure Configuration ==="
    echo "Lakerunner needs a PostgreSQL database and S3-compatible storage."
    echo "You can use local installations or connect to existing infrastructure."
    echo

    get_input "Do you want to install PostgreSQL locally? (Y/n)" "Y" "INSTALL_POSTGRES"
    if [[ "$INSTALL_POSTGRES" =~ ^[Yy]$ ]] || [ -z "$INSTALL_POSTGRES" ]; then
        INSTALL_POSTGRES=true
        print_status "Will install PostgreSQL locally"
    else
        INSTALL_POSTGRES=false
        print_status "Will use existing PostgreSQL"
        get_input "Enter PostgreSQL host" "" "POSTGRES_HOST"
        get_input "Enter PostgreSQL port" "5432" "POSTGRES_PORT"
        get_input "Enter PostgreSQL database name" "lakerunner" "POSTGRES_DB"
        get_input "Enter PostgreSQL username" "lakerunner" "POSTGRES_USER"
        get_input "Enter PostgreSQL password" "" "POSTGRES_PASSWORD"
    fi

    get_input "Do you want to install MinIO locally? (Y/n)" "Y" "INSTALL_MINIO"
    if [[ "$INSTALL_MINIO" =~ ^[Yy]$ ]] || [ -z "$INSTALL_MINIO" ]; then
        INSTALL_MINIO=true
        print_status "Will install MinIO locally"
    else
        INSTALL_MINIO=false
        print_status "Will use existing S3-compatible storage"
        get_input "Enter S3 access key" "" "S3_ACCESS_KEY"
        get_input "Enter S3 secret key" "" "S3_SECRET_KEY"
        get_input "Enter S3 region" "us-east-1" "S3_REGION"
        get_input "Enter S3 bucket name" "lakerunner" "S3_BUCKET"

    fi

    get_input "Do you want to install Kafka locally? (Y/n)" "Y" "INSTALL_KAFKA"
    if [[ "$INSTALL_KAFKA" =~ ^[Yy]$ ]] || [ -z "$INSTALL_KAFKA" ]; then
        INSTALL_KAFKA=true
        print_status "Will install Kafka locally"
    else
        INSTALL_KAFKA=false
        print_status "Will use existing Kafka"
        get_input "Enter Kafka bootstrap servers" "localhost:9092" "KAFKA_BOOTSTRAP_SERVERS"
        get_input "Enter Kafka username (leave empty if no auth)" "" "KAFKA_USERNAME"
        if [ -n "$KAFKA_USERNAME" ]; then
            get_input "Enter Kafka password" "" "KAFKA_PASSWORD"
        fi
    fi

    echo
    echo "=== SQS Configuration (Optional) ==="
    if [ "$INSTALL_MINIO" = true ]; then
        echo "Note: SQS is not needed when using local MinIO. HTTP webhook is sufficient."
        echo "SQS is recommended for production AWS S3 deployments."
        echo
        USE_SQS=false
        print_status "Will use HTTP webhook for event notifications"
    else
        echo "Note: For external S3 storage, you can use either:"
        echo "1. HTTP webhook (simpler, works with any S3-compatible storage)"
        echo "2. SQS queue (recommended for production AWS S3)"
        echo

        get_input "Do you want to configure SQS for event notifications? (y/N)" "N" "USE_SQS"
        if [[ "$USE_SQS" =~ ^[Yy]$ ]]; then
            USE_SQS=true
            print_status "Will configure SQS for event notifications"

            get_input "Enter SQS queue URL" "" "SQS_QUEUE_URL"
            get_input "Enter SQS region" "$S3_REGION" "SQS_REGION"

            echo
            echo "=== SQS Setup Instructions ==="
            echo "You'll need to manually configure:"
            echo "1. S3 bucket notifications to send events to your SQS queue"
            echo "2. SQS queue policy to allow S3 to send messages"
            echo "3. IAM permissions for Lakerunner to read from SQS"
            echo
            echo "For detailed setup instructions, visit:"
            echo "https://github.com/cardinalhq/lakerunner"
            echo
            read -p "Press Enter to continue..."
        else
            USE_SQS=false
            print_status "Will use HTTP webhook for event notifications"
        fi
    fi
}

get_telemetry_preferences() {
    echo
    echo "=== Telemetry Configuration ==="
    echo "Lakerunner can process logs, metrics, and traces."
    echo "Choose which telemetry types you want to enable:"
    echo

    get_input "Enable logs processing? (Y/n)" "Y" "ENABLE_LOGS_CHOICE"
    if [[ "$ENABLE_LOGS_CHOICE" =~ ^[Yy]$ ]] || [ -z "$ENABLE_LOGS_CHOICE" ]; then
        ENABLE_LOGS=true
        print_status "Will enable logs processing"
    else
        ENABLE_LOGS=false
        print_status "Will disable logs processing"
    fi

    get_input "Enable metrics processing? (Y/n)" "Y" "ENABLE_METRICS_CHOICE"
    if [[ "$ENABLE_METRICS_CHOICE" =~ ^[Yy]$ ]] || [ -z "$ENABLE_METRICS_CHOICE" ]; then
        ENABLE_METRICS=true
        print_status "Will enable metrics processing"
    else
        ENABLE_METRICS=false
        print_status "Will disable metrics processing"
    fi

    get_input "Enable traces processing? (Y/n)" "Y" "ENABLE_TRACES_CHOICE"
    if [[ "$ENABLE_TRACES_CHOICE" =~ ^[Yy]$ ]] || [ -z "$ENABLE_TRACES_CHOICE" ]; then
        ENABLE_TRACES=true
        print_status "Will enable traces processing"
    else
        ENABLE_TRACES=false
        print_status "Will disable traces processing"
    fi

    # Ensure at least one telemetry type is enabled
    if [ "$ENABLE_LOGS" = false ] && [ "$ENABLE_METRICS" = false ] && [ "$ENABLE_TRACES" = false ]; then
        print_warning "At least one telemetry type must be enabled. Enabling all three."
        ENABLE_LOGS=true
        ENABLE_METRICS=true
        ENABLE_TRACES=true
    fi

    echo
    echo "=== Cardinal Telemetry Collection ==="
    echo "Lakerunner can send <0.1% of telemetry data to Cardinal for automatic intelligent alerts."
    echo "This helps improve the product and provides proactive monitoring."
    echo

    if [ -n "$LAKERUNNER_CARDINAL_APIKEY" ]; then
        ENABLE_CARDINAL_TELEMETRY=true
        CARDINAL_API_KEY="$LAKERUNNER_CARDINAL_APIKEY"
        print_status "Cardinal telemetry collection enabled (using LAKERUNNER_CARDINAL_APIKEY)"
    else
        get_input "Would you like to enable Cardinal telemetry collection? (y/N)" "N" "ENABLE_CARDINAL_TELEMETRY"

        if [[ "$ENABLE_CARDINAL_TELEMETRY" =~ ^[Yy]$ ]]; then
            ENABLE_CARDINAL_TELEMETRY=true
            print_status "Cardinal telemetry collection enabled"
            get_cardinal_api_key
        else
            ENABLE_CARDINAL_TELEMETRY=false
            print_status "Cardinal telemetry collection disabled"
        fi
    fi
}

get_lakerunner_credentials() {
    echo
    echo "=== Lakerunner Credentials ==="
    echo "Lakerunner needs an organization ID and API key for authentication."
    echo

    get_input "Enter organization ID (or press Enter for default)" "151f346b-967e-4c94-b97a-581898b5b457" "ORG_ID"
    get_input "Enter API key (or press Enter for default)" "test-key" "API_KEY"
}

get_cardinal_api_key() {
    print_status "To enable Cardinal telemetry, you need to create a Cardinal API key."
    print_status "Please follow these steps:"
    echo
    print_status "1. Open your browser and go to: ${BLUE}https://app.cardinalhq.io${NC}"
    print_status "2. Sign up or log in to your account"
    print_status "3. Navigate to the API Keys section"
    print_status "4. Create a new API key"
    print_status "5. Copy the API key"
    echo
    print_warning "The API key will be stored in values-local.yaml. Keep it secure!"
    echo

    while true; do
        read -s -p "Enter your Cardinal API key: " api_key
        echo

        if [[ -n "$api_key" ]]; then
            # Validate API key format (basic check)
            if [[ "$api_key" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                CARDINAL_API_KEY="$api_key"
                break
            else
                print_error "Invalid API key format. Please enter a valid API key."
            fi
        else
            print_error "API key cannot be empty. Please enter a valid API key."
        fi
    done
}

generate_random_string() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 32
    else
        cat /dev/urandom 2>/dev/null | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1
    fi
}

install_minio() {
    if [ "$INSTALL_MINIO" = true ]; then
        print_status "Installing MinIO..."

        if helm list | grep -q "minio"; then
            print_warning "MinIO is already installed. Skipping..."
            return
        fi

        if [ "$SKIP_HELM_REPO_UPDATES" != true ]; then
            helm repo add minio https://charts.min.io/ >/dev/null 2>&1 || true
            helm repo update >/dev/null  2>&1
        fi

        helm install minio minio/minio \
            --namespace "$NAMESPACE" \
            --set accessKey=minioadmin \
            --set secretKey=minioadmin \
            --set mode=standalone \
            --set persistence.enabled=true \
            --set persistence.size=10Gi \
            --set service.type=ClusterIP \
            --set resources.requests.memory=128Mi \
            --set resources.requests.cpu=100m \
            --set service.ports[0].name=http \
            --set service.ports[0].port=9000 \
            --set service.ports[0].targetPort=9000 \
            --set service.ports[1].name=console \
            --set service.ports[1].port=9001 \
            --set service.ports[1].targetPort=9001 | output_redirect

        print_status "Waiting for MinIO to be ready..."
        kubectl wait --for=condition=ready pod -l app=minio -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1

        print_success "MinIO installed successfully"
    else
        print_status "Skipping MinIO installation (using existing S3 storage)"
    fi
}

install_postgresql() {
    if [ "$INSTALL_POSTGRES" = true ]; then
        print_status "Installing PostgreSQL..."

        if helm list | grep -q "postgres"; then
            print_warning "PostgreSQL is already installed. Skipping..."
            return
        fi

        if [ "$SKIP_HELM_REPO_UPDATES" != true ]; then
            helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
            helm repo update >/dev/null  2>&1
        fi

        helm install postgres bitnami/postgresql \
            --namespace "$NAMESPACE" \
            --set auth.username=lakerunner \
            --set auth.password=lakerunnerpass \
            --set auth.database=lakerunner \
            --set-string primary.initdb.scripts.create-config-db\\.sql="CREATE DATABASE configdb;" \
            --set persistence.enabled=true \
            --set image.repository="bitnamilegacy/postgresql" \
            --set global.security.allowInsecureImages=true \
            --set persistence.size=8Gi | output_redirect

        print_status "Waiting for PostgreSQL to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1

        print_success "PostgreSQL installed successfully"
    else
        print_status "Skipping PostgreSQL installation (using existing database)"
    fi
}

install_kafka() {
    if [ "$INSTALL_KAFKA" = true ]; then
        print_status "Installing Kafka..."

        if helm list | grep -q "kafka"; then
            print_warning "Kafka is already installed. Skipping..."
            return
        fi

        if [ "$SKIP_HELM_REPO_UPDATES" != true ]; then
            helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
            helm repo update >/dev/null  2>&1
        fi

        # Create temporary Kafka values file
        cat > /tmp/kafka-values.yaml << EOF
controller:
  replicaCount: 1

broker:
  replicaCount: 0

persistence:
  enabled: true
  size: 8Gi

auth:
  clientProtocol: plaintext
  interBrokerProtocol: plaintext

listeners:
  client:
    protocol: PLAINTEXT
  controller:
    protocol: PLAINTEXT
  interbroker:
    protocol: PLAINTEXT
  external:
    protocol: PLAINTEXT

overrideConfiguration: |
  offsets.topic.replication.factor: 1
  transaction.state.log.replication.factor: 1

service:
  ports:
    client: 9092
EOF

        helm install kafka bitnami/kafka \
            --namespace "$NAMESPACE" \
            --values /tmp/kafka-values.yaml | output_redirect

        # Clean up temporary file
        rm -f /tmp/kafka-values.yaml

        print_status "Waiting for Kafka to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1

        print_success "Kafka installed successfully"
    else
        print_status "Skipping Kafka installation (using existing Kafka)"
    fi
}


generate_values_file() {
    print_status "Generating values-local.yaml..."

    # Create generated directory if it doesn't exist
    mkdir -p generated

    AUTH_TOKEN=$(generate_random_string)
    print_status "Auto-generated internal auth token for service communication"

    # After MinIO is installed and before generating values-local.yaml, set credentials:
    if [ "$INSTALL_MINIO" = true ]; then
        MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
        MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
    else
        MINIO_ACCESS_KEY="$S3_ACCESS_KEY"
        MINIO_SECRET_KEY="$S3_SECRET_KEY"
    fi

    cat > generated/values-local.yaml << EOF
# Local development values for lakerunner
# Configured for $([ "$INSTALL_POSTGRES" = true ] && echo "local PostgreSQL" || echo "external PostgreSQL") and $([ "$INSTALL_MINIO" = true ] && echo "local MinIO" || echo "external S3 storage")

# Database configuration
database:
  create: true  # Create the secret with credentials
  secretName: "pg-credentials"
  lrdb:
    host: "$([ "$INSTALL_POSTGRES" = true ] && echo "postgres-postgresql.$NAMESPACE.svc.cluster.local" || echo "$POSTGRES_HOST")"
    port: $([ "$INSTALL_POSTGRES" = true ] && echo "5432" || echo "$POSTGRES_PORT")
    name: "$([ "$INSTALL_POSTGRES" = true ] && echo "lakerunner" || echo "$POSTGRES_DB")"
    username: "$([ "$INSTALL_POSTGRES" = true ] && echo "lakerunner" || echo "$POSTGRES_USER")"
    password: "$([ "$INSTALL_POSTGRES" = true ] && echo "lakerunnerpass" || echo "$POSTGRES_PASSWORD")"
    sslMode: "$([ "$INSTALL_POSTGRES" = true ] && echo "disable" || echo "require")"  # Disable SSL for local development
configdb:
  create: true  # Create the secret with credentials
  secretName: "lakerunner-configdb-credentials"
  lrdb:
    host: "$([ "$INSTALL_POSTGRES" = true ] && echo "postgres-postgresql.$NAMESPACE.svc.cluster.local" || echo "$POSTGRES_HOST")"
    port: $([ "$INSTALL_POSTGRES" = true ] && echo "5432" || echo "$POSTGRES_PORT")
    name: "$([ "$INSTALL_POSTGRES" = true ] && echo "configdb" || echo "$POSTGRES_DB")"
    username: "$([ "$INSTALL_POSTGRES" = true ] && echo "lakerunner" || echo "$POSTGRES_USER")"
    password: "$([ "$INSTALL_POSTGRES" = true ] && echo "lakerunnerpass" || echo "$POSTGRES_PASSWORD")"
    sslMode: "$([ "$INSTALL_POSTGRES" = true ] && echo "disable" || echo "require")"  # Disable SSL for local development

# Storage profiles
storageProfiles:
  source: "config"  # Use config file for storage profiles
  create: true
  yaml:
    - organization_id: "$ORG_ID"
      instance_num: 1
      collector_name: "lakerunner"
      cloud_provider: "aws"  # Always use "aws" for S3-compatible storage (including MinIO)
      region: "$([ "$INSTALL_MINIO" = true ] && echo "local" || echo "$S3_REGION")"
      bucket: "$([ "$INSTALL_MINIO" = true ] && echo "lakerunner" || echo "$S3_BUCKET")"
      use_path_style: true
      $([ "$INSTALL_MINIO" = true ] && echo "endpoint: \"http://minio.$NAMESPACE.svc.cluster.local:9000\"" || echo "# endpoint: \"\"")

# API keys for local development
apiKeys:
  source: "config"  # Use config file for API keys
  create: true
  secretName: "apikeys"
  yaml:
    - organization_id: "$ORG_ID"
      keys:
        - "$API_KEY"

# Authentication token for query-api to query-worker communication
auth:
  token:
    create: true
    secretName: "query-token"
    secretValue: "$AUTH_TOKEN"

# Cloud provider configuration
cloudProvider:
  provider: "aws"  # Using AWS provider for S3-compatible storage (including MinIO)
  aws:
    region: "$([ "$INSTALL_MINIO" = true ] && echo "us-east-1" || echo "$S3_REGION")"  # This doesn't matter for MinIO but is required
    create: true  # Create the secret with credentials
    secretName: "aws-credentials"
    inject: true
    accessKeyId: "$MINIO_ACCESS_KEY"
    secretAccessKey: "$MINIO_SECRET_KEY"
  duckdb:
    create: true
    secretName: "duckdb-credentials"
    accessKeyId: "$MINIO_ACCESS_KEY"
    secretAccessKey: "$MINIO_SECRET_KEY"

kafkaTopics:
  config:
    version: 2
    defaults:
      partitionCount: 1
      replicationFactor: 1

# Kafka configuration
kafka:
  enabled: $INSTALL_KAFKA
$([ "$INSTALL_KAFKA" = true ] && echo "  brokers: \"kafka.$NAMESPACE.svc.cluster.local:9092\"" || echo "  brokers: \"$KAFKA_BOOTSTRAP_SERVERS\"")
  sasl:
$([ -n "$KAFKA_USERNAME" ] && [ -n "$KAFKA_PASSWORD" ] && echo "    enabled: true" || echo "    enabled: false")
$([ -n "$KAFKA_USERNAME" ] && echo "    username: \"$KAFKA_USERNAME\"" || echo "#   username: \"\"")
$([ -n "$KAFKA_PASSWORD" ] && echo "    password: \"$KAFKA_PASSWORD\"" || echo "#   password: \"\"")
  tls:
    enabled: $([ "$INSTALL_KAFKA" = true ] && echo "false" || echo "true")

# Global configuration
global:
  resources:
    enabled: false
  autoscaling:
    mode: disabled
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "  # Cardinal telemetry configuration" || echo "  # Cardinal telemetry configuration (disabled)")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "  cardinal:" || echo "  # cardinal:")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    apiKey: \"$CARDINAL_API_KEY\"" || echo "  #   apiKey: \"\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && [ -n "$LAKERUNNER_CARDINAL_ENV" ] && echo "    env: \"$LAKERUNNER_CARDINAL_ENV\"" || echo "")
  # Global environment variables for all Lakerunner components
  # env:

# PubSub configuration
pubsub:
  HTTP:
    enabled: $([ "$USE_SQS" = true ] && echo "false" || echo "true")
    replicas: 1

  SQS:
    enabled: $([ "$USE_SQS" = true ] && echo "true" || echo "false")
    $([ "$USE_SQS" = true ] && echo "queueURL: \"$SQS_QUEUE_URL\"" || echo "# queueURL: \"\"")
    $([ "$USE_SQS" = true ] && echo "region: \"$SQS_REGION\"" || echo "# region: \"\"")

collector:
  enabled: false

# Reduce resource requirements for local development
setup:
  enabled: true
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi

ingestLogs:
  enabled: $([ "$ENABLE_LOGS" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 200m
      memory: 100Mi
    limits:
      cpu: 500m
      memory: 200Mi
  autoscaling:
    enabled: false  # Disable autoscaling for local development

ingestMetrics:
  enabled: $([ "$ENABLE_METRICS" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi
  autoscaling:
    enabled: false  # Disable autoscaling for local development

ingestTraces:
  enabled: $([ "$ENABLE_TRACES" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi
  autoscaling:
    enabled: false

compactLogs:
  enabled: $([ "$ENABLE_LOGS" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi
  autoscaling:
    enabled: false

compactMetrics:
  enabled: $([ "$ENABLE_METRICS" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi
  autoscaling:
    enabled: false

compactTraces:
  enabled: $([ "$ENABLE_TRACES" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi
  autoscaling:
    enabled: false

rollupMetrics:
  enabled: $([ "$ENABLE_METRICS" = true ] && echo "true" || echo "false")
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
    limits:
      cpu: 1000m
      memory: 500Mi
  autoscaling:
    enabled: false

sweeper:
  enabled: true
  replicas: 1
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    limits:
      cpu: 100m
      memory: 100Mi

queryApi:
  enabled: true
  replicas: 1
  resources:
    requests:
      cpu: 1000m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 1Gi
  temporaryStorage:
    size: "8Gi"  # Reduce for local development

queryWorker:
  enabled: true
  replicas: 2
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 500m
      memory: 1Gi

# Grafana configuration
grafana:
  enabled: true
  replicas: 1
  image:
    repository: grafana/grafana
    tag: latest
    pullPolicy: Always
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
  service:
    type: ClusterIP
    port: 3000
  plugins:
    - "https://github.com/cardinalhq/cardinalhq-lakerunner-datasource/releases/download/v1.2.0-rc.12/cardinalhq-lakerunner-datasource.zip;cardinalhq-lakerunner-datasource"
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Cardinal Lakerunner
          type: cardinalhq-lakerunner-datasource
          access: proxy
          editable: true
          jsonData:
            customPath: "http://lakerunner-query-api-v2.$NAMESPACE.svc.cluster.local:8080"
          secureJsonData:
            apiKey: "$API_KEY"
EOF

    print_success "generated/values-local.yaml generated successfully"
}


# Function to install Lakerunner
install_lakerunner() {
    print_status "Installing Lakerunner in namespace: $NAMESPACE"

    helm install lakerunner oci://public.ecr.aws/cardinalhq.io/lakerunner \
        --version $LAKERUNNER_VERSION \
        --values generated/values-local.yaml \
        --namespace $NAMESPACE | output_redirect
    print_success "Lakerunner installed successfully in namespace: $NAMESPACE"
}

# Function to wait for services to be ready
wait_for_services() {
    print_status "Waiting for Lakerunner services to be ready in namespace: $NAMESPACE"
    # Check if setup job exists and wait for it to complete
    if kubectl get job lakerunner-setup -n "$NAMESPACE" >/dev/null 2>&1; then
        print_status "Waiting for setup job to complete..."
        kubectl wait --for=condition=complete job/lakerunner-setup -n "$NAMESPACE" --timeout=600s
    else
        print_status "Setup job not found (may have already completed or not needed for upgrade)"
    fi
    print_status "Waiting for query-api service..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=lakerunner,app.kubernetes.io/component=query-api-v2 -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1 || true
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=lakerunner,app.kubernetes.io/component=grafana -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1 || true
    print_success "All services are ready in namespace: $NAMESPACE"
}


display_connection_info() {
    print_success "Lakerunner installation completed successfully!"
    echo
    echo "=== Installation Summary ==="
    echo

    echo "Telemetry Configuration:"
    if [ "$ENABLE_LOGS" = true ]; then
        echo "  Logs: Enabled"
    else
        echo "  Logs: Disabled"
    fi
    if [ "$ENABLE_METRICS" = true ]; then
        echo "  Metrics: Enabled"
    else
        echo "  Metrics: Disabled"
    fi
    if [ "$ENABLE_TRACES" = true ]; then
        echo "  Traces: Enabled"
    else
        echo "  Traces: Disabled"
    fi

    echo
    echo "Infrastructure:"
    if [ "$INSTALL_POSTGRES" = true ]; then
        echo "  PostgreSQL: Installed"
    fi

    if [ "$INSTALL_MINIO" = true ]; then
        echo "  Storage: MinIO Installed"
    else
        echo "  Storage: External S3 ($S3_BUCKET)"
    fi

    if [ "$INSTALL_KAFKA" = true ]; then
        echo "  Kafka: Installed"
    fi

    if [ "$ENABLE_CARDINAL_TELEMETRY" = true ]; then
        echo "  Cardinal Telemetry: Enabled"
        # Check if we're in test mode based on the environment variable
        if [ -n "$LAKERUNNER_CARDINAL_ENV" ] && [ "$LAKERUNNER_CARDINAL_ENV" = "test" ]; then
            echo "  Cardinal Dashboard: https://app.test.cardinalhq.io"
        else
            echo "  Cardinal Dashboard: https://app.cardinalhq.io"
        fi
    else
        echo "  Cardinal Telemetry: Disabled"
    fi
    echo

    # Demo App Information (only if installed)
    if [ "$INSTALL_OTEL_DEMO" = true ]; then
        echo "=== Demo Applications ==="
        echo "OpenTelemetry demo applications have been installed in the 'otel-demo' namespace."
        echo "These apps generate sample telemetry data for testing Lakerunner functionality."
        echo
        echo "To access the demo applications:"
        echo "  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=frontend-proxy -n otel-demo --timeout=300s"
        echo "  kubectl port-forward svc/frontend-proxy 8080:8080 -n otel-demo"
        echo "  Then visit: http://localhost:8080"
        echo
    fi

    # MinIO Console Access (only if MinIO was installed)
    if [ "$INSTALL_MINIO" = true ]; then
        # Get MinIO credentials
        MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
        MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")

        echo "=== MinIO Console Access ==="
        echo "To access MinIO Console:"
        echo "  kubectl port-forward svc/minio-console 9001:9001 -n $NAMESPACE"
        echo "  Then visit: http://localhost:9001"
        echo "  Access Key: $MINIO_ACCESS_KEY"
        echo "  Secret Key: $MINIO_SECRET_KEY"
        echo
    fi

    # CLI Access
    echo "=== Lakerunner CLI Access ==="
    echo "To use lakerunner-cli:"
    echo "  kubectl port-forward svc/lakerunner-query-api-v2 8080:8080 -n $NAMESPACE"
    echo "  Download CLI from: https://github.com/cardinalhq/lakerunner-cli/releases"
    echo "  Then run: lakerunner-cli --endpoint http://localhost:8080 --api-key $API_KEY"
    echo

    # Grafana Access
    echo "=== Grafana Dashboard Access ==="
    echo "To access Grafana:"
    echo "  kubectl port-forward svc/lakerunner-grafana 3000:3000 -n $NAMESPACE"
    echo "  Then visit: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin"
    echo "  Datasource: Cardinal (pre-configured)"
    echo

    # Only show PubSub HTTP endpoint if MinIO was NOT installed and not using SQS
    if [ "$INSTALL_MINIO" = false ] && [ "$USE_SQS" = false ]; then
        echo "=== Event Notification Configuration ==="
        echo "Lakerunner PubSub HTTP Endpoint:"
        echo "  URL: http://lakerunner-pubsub-http.$NAMESPACE.svc.cluster.local:8080/"
        echo
    fi

    echo "=== Next Steps ==="

    # Only show MinIO-specific instructions if MinIO was NOT installed
    if [ "$INSTALL_MINIO" = false ]; then
        echo "1. Ensure your S3 bucket '$S3_BUCKET' exists and is accessible"

        if [ "$USE_SQS" = true ]; then
            echo "2. Configure S3 bucket notifications to send events to your SQS queue:"
            echo "   - Queue ARN: arn:aws:sqs:$SQS_REGION:$(echo $SQS_QUEUE_URL | cut -d'/' -f4):$(echo $SQS_QUEUE_URL | cut -d'/' -f5)"
            echo "   - Event types: s3:ObjectCreated:*"
            echo "3. Configure SQS queue policy to allow S3 to send messages"
            echo "4. Ensure IAM permissions for Lakerunner to read from SQS"
        else
            echo "2. Configure event notifications in your S3-compatible storage:"
            echo "   - Add event notification pointing to:"
            echo "     http://lakerunner-pubsub-http.$NAMESPACE.svc.cluster.local:8080/"
            echo "3. The event notification ARN should appear in the bucket configuration"
        fi
    fi

    echo
    echo "For further information, visit: https://github.com/cardinalhq/lakerunner"
    echo

}

ask_install_otel_demo() {
    echo
    echo "=== OpenTelemetry Demo Apps ==="
    echo "Would you like to install the OpenTelemetry demo applications?"
    echo "This will deploy a sample e-commerce application that generates"
    echo "logs, metrics, and traces to demonstrate Lakerunner in action."
    echo

    get_input "Install OTEL demo apps? (Y/n)" "Y" "INSTALL_OTEL_DEMO"

    if [[ "$INSTALL_OTEL_DEMO" =~ ^[Yy]$ ]] || [ -z "$INSTALL_OTEL_DEMO" ]; then
        INSTALL_OTEL_DEMO=true
        print_status "Will install OpenTelemetry demo apps"
    else
        INSTALL_OTEL_DEMO=false
        print_status "Skipping OpenTelemetry demo apps installation"
    fi
}

display_configuration_summary() {
    echo
    echo "=========================================="
    echo "    Configuration Summary"
    echo "=========================================="
    echo

    echo "Namespace: $NAMESPACE"
    echo

    echo "Infrastructure Configuration:"
    if [ "$INSTALL_POSTGRES" = true ]; then
        echo "  PostgreSQL: Local installation"
    else
        echo "  PostgreSQL: External ($POSTGRES_HOST:$POSTGRES_PORT/$POSTGRES_DB)"
    fi

    if [ "$INSTALL_MINIO" = true ]; then
        echo "  Storage: Local MinIO"
    else
        echo "  Storage: External S3 ($S3_BUCKET)"
    fi

    if [ "$INSTALL_KAFKA" = true ]; then
        echo "  Kafka: Local installation"
    else
        echo "  Kafka: External ($KAFKA_BOOTSTRAP_SERVERS)"
    fi

    if [ "$USE_SQS" = true ]; then
        echo "  Event Notifications: SQS ($SQS_QUEUE_URL)"
    else
        echo "  Event Notifications: HTTP webhook"
    fi
    echo

    echo "Telemetry Configuration:"
    if [ "$ENABLE_LOGS" = true ]; then
        echo "  Logs: Enabled"
    else
        echo "  Logs: Disabled"
    fi
    if [ "$ENABLE_METRICS" = true ]; then
        echo "  Metrics: Enabled"
    else
        echo "  Metrics: Disabled"
    fi
    if [ "$ENABLE_TRACES" = true ]; then
        echo "  Traces: Enabled"
    else
        echo "  Traces: Disabled"
    fi

    if [ "$ENABLE_CARDINAL_TELEMETRY" = true ]; then
        echo "  Cardinal Telemetry: Enabled"
    else
        echo "  Cardinal Telemetry: Disabled"
    fi
    echo

    echo "Demo Applications:"
    if [ "$INSTALL_OTEL_DEMO" = true ]; then
        echo "  OpenTelemetry Demo: Will be installed"
    else
        echo "  OpenTelemetry Demo: Will not be installed"
    fi
    echo
}

confirm_installation() {
    echo "=========================================="
    echo "    Installation Confirmation"
    echo "=========================================="
    echo

    get_input "Proceed with installation? (Y/n)" "Y" "CONFIRM_INSTALL"

    if [[ "$CONFIRM_INSTALL" =~ ^[Nn]$ ]]; then
        print_status "Installation cancelled by user"
        exit 0
    fi

    echo
    print_status "Proceeding with installation..."
    echo
}

generate_otel_demo_values() {
    print_status "Generating OTEL demo values file..."

    # Create generated directory if it doesn't exist
    mkdir -p generated

    # Get MinIO credentials
    MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
    MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")

    cat > generated/otel-demo-values.yaml << EOF
components:
  load-generator:
    resources:
      limits:
        cpu: 250m
        memory: 512Mi
    env:
      - name: LOCUST_WEB_HOST
        value: "0.0.0.0"
      - name: LOCUST_WEB_PORT
        value: "8089"
      - name: LOCUST_USERS
        value: "3"
      - name: LOCUST_SPAWN_RATE
        value: "1"
      - name: LOCUST_HOST
        value: http://frontend-proxy:8080
      - name: LOCUST_HEADLESS
        value: "false"
      - name: LOCUST_AUTOSTART
        value: "true"
      - name: LOCUST_BROWSER_TRAFFIC_ENABLED
        value: "true"
      - name: PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION
        value: python
      - name: FLAGD_HOST
        value: flagd
      - name: FLAGD_OFREP_PORT
        value: "8016"
      - name: OTEL_EXPORTER_OTLP_ENDPOINT
        value: http://otel-collector:4317
opentelemetry-collector:
  config:
    receivers:
      otlp:
        protocols:
          grpc:
            endpoint: 0.0.0.0:4317
          http:
            endpoint: 0.0.0.0:4318
    processors:
      batch:
        timeout: 10s
    connectors:
      spanmetrics: {}
    exporters:
      awss3/metrics:
        marshaler: otlp_proto
        s3uploader:
          s3_bucket: "lakerunner"
          s3_prefix: "otel-raw/$ORG_ID/lakerunner"
          endpoint: http://minio.$NAMESPACE.svc.cluster.local:9000
          compression: "gzip"
          s3_force_path_style: true
          disable_ssl: true
      awss3/logs:
        marshaler: otlp_proto
        s3uploader:
          s3_bucket: "lakerunner"
          s3_prefix: "otel-raw/$ORG_ID/lakerunner"
          endpoint: http://minio.$NAMESPACE.svc.cluster.local:9000
          compression: "gzip"
          s3_force_path_style: true
          disable_ssl: true
      awss3/traces:
        marshaler: otlp_proto
        s3uploader:
          s3_bucket: "lakerunner"
          s3_prefix: "otel-raw/$ORG_ID/lakerunner"
          endpoint: http://minio.$NAMESPACE.svc.cluster.local:9000
          compression: "gzip"
          s3_force_path_style: true
          disable_ssl: true
    service:
      pipelines:
        metrics:
          receivers: [otlp, spanmetrics]
          processors:
            - batch
          exporters: [awss3/metrics]
        logs:
          receivers: [otlp]
          processors:
            - batch
          exporters: [awss3/logs]
        traces:
          receivers: [otlp]
          exporters: [spanmetrics, awss3/traces]
      telemetry:
        metrics:
          level: none
  extraEnvs:
    - name: AWS_ACCESS_KEY_ID
      value: "$MINIO_ACCESS_KEY"
    - name: AWS_SECRET_ACCESS_KEY
      value: "$MINIO_SECRET_KEY"
jaeger:
  enabled: false
prometheus:
  enabled: false
grafana:
  enabled: false
opensearch:
  enabled: false
EOF

    print_success "generated/otel-demo-values.yaml generated successfully"
}

setup_minio_webhooks() {
    if [ "$INSTALL_MINIO" = true ]; then
        print_status "Setting up MinIO webhooks for Lakerunner event notifications..."

        # Check if lakerunner bucket exists and create if needed
        MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
        MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
        S3_BUCKET=${S3_BUCKET:-lakerunner}

        kubectl exec -n "$NAMESPACE" deployment/minio -- mc alias set minio http://localhost:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY >/dev/null 2>&1

        if ! kubectl exec -n "$NAMESPACE" deployment/minio -- mc ls minio/$S3_BUCKET >/dev/null 2>&1; then
            print_warning "lakerunner bucket does not exist. Creating it..."
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc mb minio/lakerunner
            print_success "lakerunner bucket created successfully"
        else
            print_success "lakerunner bucket already exists"
        fi

        # Configure webhook notifications
        print_status "Configuring MinIO webhook notifications..."
        if kubectl exec -n "$NAMESPACE" deployment/minio -- mc admin config set minio notify_webhook:create_object endpoint="http://lakerunner-pubsub-http.$NAMESPACE.svc.cluster.local:8080/" 2>/dev/null; then
            print_success "Webhook configuration set successfully"
        else
            print_warning "Failed to set webhook configuration, continuing..."
        fi

        print_status "Restarting MinIO to apply configuration..."
        kubectl rollout restart deployment/minio -n "$NAMESPACE" >/dev/null 2>&1

        print_status "Waiting for MinIO to restart..."
        kubectl rollout status deployment/minio -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1

        # Wait a bit more for MinIO to be fully ready
        sleep 5
        print_success "MinIO restarted successfully"

        # Re-setup mc alias after pod restart
        print_status "Re-establishing MinIO connection..."
        kubectl exec -n "$NAMESPACE" deployment/minio -- mc alias set minio http://localhost:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY >/dev/null 2>&1

        # Add event notifications for different telemetry types
        print_status "Setting up event notifications..."
        kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "logs-raw" 2>/dev/null || print_warning "Failed to add logs-raw event notification"
        kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "metrics-raw" 2>/dev/null || print_warning "Failed to add metrics-raw event notification"
        kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "traces-raw" 2>/dev/null || print_warning "Failed to add traces-raw event notification"
        kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "otel-raw" 2>/dev/null || print_warning "Failed to add otel-raw event notification"

        print_success "MinIO webhooks configured successfully for Lakerunner event notifications"
    else
        print_status "Skipping MinIO webhook setup (using external S3 storage)"
    fi
}

install_otel_demo() {
    if [ "$INSTALL_OTEL_DEMO" = true ]; then
        print_status "Installing OpenTelemetry demo apps..."

        # Check if lakerunner bucket exists (required for OTEL demo to work)
        if [ "$INSTALL_MINIO" = true ]; then
            print_status "Checking if lakerunner bucket exists in MinIO..."
            MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
            MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc alias set minio http://localhost:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY >/dev/null 2>&1
            if ! kubectl exec -n "$NAMESPACE" deployment/minio -- mc ls minio/lakerunner >/dev/null 2>&1; then
                print_error "lakerunner bucket does not exist. MinIO setup may have failed."
                exit 1
            fi
        else
            print_warning "Using external S3 storage. Please ensure the 'lakerunner' bucket exists."
            print_warning "The OTEL demo apps will fail if the bucket doesn't exist."
            read -p "Press Enter to continue..."
        fi

        kubectl get namespace "otel-demo" >/dev/null 2>&1 || kubectl create namespace "otel-demo" >/dev/null 2>&1

        # Add OpenTelemetry Helm repository
        if [ "$SKIP_HELM_REPO_UPDATES" != true ]; then
            helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
            helm repo update >/dev/null  2>&1
        fi

        helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
            --namespace otel-demo \
            --values generated/otel-demo-values.yaml | output_redirect

        print_success "OpenTelemetry demo apps installed successfully"
        echo
        echo "=== OpenTelemetry Demo Apps ==="
        echo "Demo applications have been installed in the 'otel-demo' namespace."
        echo "These apps will generate sample telemetry data that will be:"
        echo "1. Collected by the OpenTelemetry Collector"
        echo "2. Exported to MinIO S3 storage"
        echo "3. Processed by Lakerunner"
        echo "4. Available in Grafana dashboard"
        echo
        echo "To access the demo applications, run the following:"
        echo " kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=frontend-proxy -n otel-demo --timeout=300s "
        echo " kubectl port-forward svc/frontend-proxy 8080:8080 -n otel-demo "
        echo "Then visit http://localhost:8080"
        echo "The demo apps will continuously generate logs, metrics, and traces"
        echo "that will flow through Lakerunner for processing and analysis."
        echo
    else
        print_status "Skipping OpenTelemetry demo apps installation"
    fi
}

# Parse command line arguments
parse_args() {
    SIGNALS_FLAG=""
    STANDALONE_FLAG=false
    SKIP_HELM_REPO_UPDATES=false
    VERBOSE=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --signals)
                SIGNALS_FLAG="$2"
                shift 2
                ;;
            --standalone)
                STANDALONE_FLAG=true
                shift
                ;;
            --skip-helm-repo-updates)
                SKIP_HELM_REPO_UPDATES=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

show_help() {
    echo "Lakerunner Installation Script"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --signals SIGNALS         Specify which telemetry signals to enable"
    echo "                            Options: all, logs, metrics, traces"
    echo "                            Multiple signals can be comma-separated"
    echo "                            Examples: --signals all"
    echo "                                     --signals metrics"
    echo "                                     --signals logs,metrics,traces"
    echo "  --standalone              Install in standalone mode with minimal interaction"
    echo "                            Automatically enables logs and metrics, installs all"
    echo "                            local infrastructure (PostgreSQL, MinIO, Kafka)"
    echo "                            Uses default namespace 'lakerunner' and default credentials"
    echo "  --skip-helm-repo-updates  Skip running 'helm repo update' commands during installation"
    echo "                            Useful when helm repos are already up to date or when"
    echo "                            working in environments with restricted network access"
    echo "  --verbose                 Show detailed output from helm install commands"
    echo "                            By default, helm output is hidden to reduce noise"
    echo "  --help, -h               Show this help message"
    echo
}

# Parse signals from the --signals flag
parse_signals() {
    if [ -n "$SIGNALS_FLAG" ]; then
        # Convert to lowercase and remove spaces
        signals=$(echo "$SIGNALS_FLAG" | tr '[:upper:]' '[:lower:]' | tr -d ' ')

        # Initialize all signals to false
        ENABLE_LOGS=false
        ENABLE_METRICS=false
        ENABLE_TRACES=false

        if [ "$signals" = "all" ]; then
            ENABLE_LOGS=true
            ENABLE_METRICS=true
            ENABLE_TRACES=true
            print_status "Signals: Enabling all telemetry types (logs, metrics, traces)"
        else
            # Split by comma and process each signal
            IFS=',' read -ra SIGNAL_ARRAY <<< "$signals"
            enabled_signals=()

            for signal in "${SIGNAL_ARRAY[@]}"; do
                case "$signal" in
                    logs)
                        ENABLE_LOGS=true
                        enabled_signals+=("logs")
                        ;;
                    metrics)
                        ENABLE_METRICS=true
                        enabled_signals+=("metrics")
                        ;;
                    traces)
                        ENABLE_TRACES=true
                        enabled_signals+=("traces")
                        ;;
                    *)
                        print_error "Invalid signal: $signal"
                        echo "Valid signals are: logs, metrics, traces, all"
                        exit 1
                        ;;
                esac
            done

            if [ ${#enabled_signals[@]} -eq 0 ]; then
                print_error "No valid signals specified"
                exit 1
            fi

            print_status "Signals: Enabling $(IFS=', '; echo "${enabled_signals[*]}")"
        fi

        return 0  # Signals were specified via flag
    else
        return 1  # No signals flag, should ask user
    fi
}

# Configure all settings for standalone mode
configure_standalone() {
    print_status "Configuring standalone installation..."

    # Namespace
    NAMESPACE="lakerunner"

    # Infrastructure - install everything locally
    INSTALL_POSTGRES=true
    INSTALL_MINIO=true
    INSTALL_KAFKA=true

    # Telemetry - use --signals flag if provided, otherwise default to logs and metrics
    if [ -n "$SIGNALS_FLAG" ]; then
        # --signals flag was provided, use parse_signals() to set telemetry
        parse_signals
        print_status "Using signals from --signals flag"
    else
        # No --signals flag, use standalone defaults: logs and metrics enabled, traces disabled
        ENABLE_LOGS=true
        ENABLE_METRICS=true
        ENABLE_TRACES=false
        print_status "Using standalone default signals: logs and metrics"
    fi

    # Event notifications - use HTTP webhook (not SQS)
    USE_SQS=false

    # Credentials - use defaults
    ORG_ID="151f346b-967e-4c94-b97a-581898b5b457"
    API_KEY="test-key"

    # Cardinal telemetry - check environment variable or ask user
    if [ -n "$LAKERUNNER_CARDINAL_APIKEY" ]; then
        ENABLE_CARDINAL_TELEMETRY=true
        CARDINAL_API_KEY="$LAKERUNNER_CARDINAL_APIKEY"
        print_status "Cardinal telemetry enabled (using LAKERUNNER_CARDINAL_APIKEY)"
    else
        # Ask user about Cardinal telemetry even in standalone mode
        echo
        echo "=== Cardinal Telemetry Collection ==="
        echo "Lakerunner can send <0.1% of telemetry data to Cardinal for automatic intelligent alerts."
        echo "This helps improve the product and provides proactive monitoring."
        echo

        get_input "Would you like to enable Cardinal telemetry collection? (y/N)" "N" "ENABLE_CARDINAL_TELEMETRY"

        if [[ "$ENABLE_CARDINAL_TELEMETRY" =~ ^[Yy]$ ]]; then
            ENABLE_CARDINAL_TELEMETRY=true
            print_status "Cardinal telemetry collection enabled"
            get_cardinal_api_key
        else
            ENABLE_CARDINAL_TELEMETRY=false
            print_status "Cardinal telemetry collection disabled"
        fi
    fi

    # Demo apps - install by default in standalone mode
    INSTALL_OTEL_DEMO=true

    print_status "Standalone mode configured:"
    print_status "  Namespace: $NAMESPACE"
    print_status "  Infrastructure: PostgreSQL, MinIO, Kafka (all local)"

    # Build telemetry status message
    telemetry_status=""
    [ "$ENABLE_LOGS" = true ] && telemetry_status="${telemetry_status}Logs "
    [ "$ENABLE_METRICS" = true ] && telemetry_status="${telemetry_status}Metrics "
    [ "$ENABLE_TRACES" = true ] && telemetry_status="${telemetry_status}Traces "

    if [ -z "$telemetry_status" ]; then
        telemetry_status="None enabled"
    else
        telemetry_status="${telemetry_status%% }enabled"  # Remove trailing space and add "enabled"
    fi

    print_status "  Telemetry: $telemetry_status"
    print_status "  Demo apps: Enabled"
    print_status "  Cardinal telemetry: $([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "Enabled" || echo "Disabled")"
}

main() {
    # Parse command line arguments
    parse_args "$@"

    echo "=========================================="
    echo "    Lakerunner Installation Script"
    echo "=========================================="
    echo

    check_prerequisites

    # Handle configuration based on flags
    if [ "$STANDALONE_FLAG" = true ]; then
        # Standalone mode - configure everything automatically
        configure_standalone
    else
        # Interactive mode - get all user preferences
        get_namespace
        get_infrastructure_preferences

        # Handle telemetry preferences
        if ! parse_signals; then
            # No --signals flag provided, ask user
            get_telemetry_preferences
        fi

        get_lakerunner_credentials
        ask_install_otel_demo
    fi

    # Display configuration summary
    display_configuration_summary

    # Confirm installation
    confirm_installation

    # Pre-flight check for helm repositories (now that we know the configuration)
    check_helm_repositories

    # Start installation process
    print_status "Starting installation process..."

    # Ensure namespace exists before installing anything
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE" >/dev/null 2>&1

    install_minio
    install_postgresql
    install_kafka

    generate_values_file

    install_lakerunner

    wait_for_services

    # Setup MinIO webhooks for Lakerunner event notifications (required for Lakerunner to function)
    setup_minio_webhooks

    generate_otel_demo_values

    install_otel_demo

    display_connection_info
}

main "$@"
