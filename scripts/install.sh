#!/bin/bash

# LakeRunner Install Script
# This script installs LakeRunner with local MinIO and PostgreSQL

set -e

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
    echo "LakeRunner will be installed in a Kubernetes namespace."

    get_input "Enter namespace for LakeRunner installation" "$default_namespace" "NAMESPACE"
}

get_infrastructure_preferences() {
    echo
    echo "=== Infrastructure Configuration ==="
    echo "LakeRunner needs a PostgreSQL database and S3-compatible storage."
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
            echo "3. IAM permissions for LakeRunner to read from SQS"
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
    echo "LakeRunner can process logs, metrics, and traces."
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
    echo "LakeRunner can send <0.1% of telemetry data to Cardinal for automatic intelligent alerts."
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
}

get_lakerunner_credentials() {
    echo
    echo "=== LakeRunner Credentials ==="
    echo "LakeRunner needs an organization ID and API key for authentication."
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
        
        helm repo add minio https://charts.min.io/ >/dev/null 2>&1 || true
        helm repo update >/dev/null  2>&1
        
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
            --set service.ports[1].targetPort=9001 >/dev/null  2>&1
        
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
        
        helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
        helm repo update >/dev/null  2>&1
        
        helm install postgres bitnami/postgresql \
            --namespace "$NAMESPACE" \
            --set auth.username=lakerunner \
            --set auth.password=lakerunnerpass \
            --set auth.database=lakerunner \
            --set-string primary.initdb.scripts.create-config-db\\.sql="CREATE DATABASE configdb;" \
            --set persistence.enabled=true \
            --set persistence.size=8Gi >/dev/null  2>&1
        
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
        
        helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
        helm repo update >/dev/null  2>&1
        
        helm install kafka bitnami/kafka \
            --namespace "$NAMESPACE" \
            --set persistence.enabled=true \
            --set persistence.size=8Gi \
            --set zookeeper.persistence.enabled=true \
            --set zookeeper.persistence.size=2Gi \
            --set auth.clientProtocol=plaintext \
            --set auth.interBrokerProtocol=plaintext \
            --set listeners.client.protocol=PLAINTEXT \
            --set listeners.controller.protocol=PLAINTEXT \
            --set listeners.interbroker.protocol=PLAINTEXT \
            --set listeners.external.protocol=PLAINTEXT \
            --set service.ports.client=9092 >/dev/null  2>&1
        
        print_status "Waiting for Kafka to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1
        
        print_success "Kafka installed successfully"
    else
        print_status "Skipping Kafka installation (using existing Kafka)"
    fi
}

setup_kafka_topics() {
    if [ "$INSTALL_KAFKA" = true ]; then
        print_status "Setting up Kafka topics for LakeRunner..."
        
        # Wait for Kafka to be fully ready
        print_status "Waiting for Kafka to be fully operational..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=kafka -n "$NAMESPACE" --timeout=300s >/dev/null 2>&1
        sleep 10  # Additional time for Kafka to fully initialize
        
        # Create required topics
        print_status "Creating LakeRunner Kafka topics..."
        
        # List of topics required by LakeRunner
        topics=(
            "lakerunner.objstore.ingest.logs"
            "lakerunner.objstore.ingest.metrics"
            "lakerunner.objstore.ingest.traces"
            "lakerunner.segments.logs.compact"
            "lakerunner.segments.metrics.compact"
            "lakerunner.segments.metrics.rollup"
            "lakerunner.segments.traces.compact"
        )
        
        # Find the first available Kafka pod dynamically
        KAFKA_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=kafka -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [ -z "$KAFKA_POD" ]; then
            print_error "Could not find Kafka pod in namespace $NAMESPACE"
            print_warning "Kafka topics will need to be created manually"
            return 1
        fi
        
        print_status "Using Kafka pod: $KAFKA_POD"
        
        # Test Kafka connectivity first
        print_status "Testing Kafka connectivity..."
        if ! kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- kafka-topics.sh --bootstrap-server localhost:9092 --list >/dev/null 2>&1; then
            print_error "Cannot connect to Kafka broker"
            print_warning "Kafka topics will need to be created manually"
            return 1
        fi
        
        for topic in "${topics[@]}"; do
            if kubectl exec -n "$NAMESPACE" "$KAFKA_POD" -- kafka-topics.sh \
                --bootstrap-server localhost:9092 \
                --create \
                --topic "$topic" \
                --partitions 3 \
                --replication-factor 1 \
                --if-not-exists >/dev/null 2>&1; then
                print_success "Topic $topic ready"
            else
                print_warning "Failed to create topic $topic"
            fi
        done
        
        print_success "Kafka topics setup completed"
    else
        print_status "Skipping Kafka topics setup (using existing Kafka)"
        print_warning "Please ensure the following topics exist in your external Kafka:"
        echo "  - lakerunner.objstore.ingest.logs"
        echo "  - lakerunner.objstore.ingest.metrics" 
        echo "  - lakerunner.objstore.ingest.traces"
        echo "  - lakerunner.segments.logs.compact"
        echo "  - lakerunner.segments.metrics.compact"
        echo "  - lakerunner.segments.metrics.rollup"
        echo "  - lakerunner.segments.traces.compact"
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

# Kafka configuration
$([ "$INSTALL_KAFKA" = true ] && echo "kafka:" || echo "# kafka:")
$([ "$INSTALL_KAFKA" = true ] && echo "  enabled: true" || echo "# enabled: false")
$([ "$INSTALL_KAFKA" = true ] && echo "  bootstrapServers: \"kafka.$NAMESPACE.svc.cluster.local:9092\"" || echo "# bootstrapServers: \"$KAFKA_BOOTSTRAP_SERVERS\"")
$([ "$INSTALL_KAFKA" = false ] && [ -n "$KAFKA_USERNAME" ] && echo "# auth:" || echo "# # auth:")
$([ "$INSTALL_KAFKA" = false ] && [ -n "$KAFKA_USERNAME" ] && echo "#   username: \"$KAFKA_USERNAME\"" || echo "# #   username: \"\"")
$([ "$INSTALL_KAFKA" = false ] && [ -n "$KAFKA_PASSWORD" ] && echo "#   password: \"$KAFKA_PASSWORD\"" || echo "# #   password: \"\"")

# Global configuration
global:
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "  # Cardinal telemetry configuration" || echo "  # Cardinal telemetry configuration (disabled)")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "  cardinal:" || echo "  # cardinal:")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    apiKey: \"$CARDINAL_API_KEY\"" || echo "  #   apiKey: \"\"")
  # Required empty objects to prevent nil pointer errors
  labels: {}
  annotations: {}
  # Global environment variables for all LakeRunner components
  env:
$([ "$INSTALL_KAFKA" = true ] && echo "    # Kafka configuration for LakeRunner" || echo "    # Kafka configuration (disabled)")
$([ "$INSTALL_KAFKA" = true ] && echo "    - name: LAKERUNNER_FLY_ENABLED" || echo "    # - name: LAKERUNNER_FLY_ENABLED")
$([ "$INSTALL_KAFKA" = true ] && echo "      value: \"true\"" || echo "    #   value: \"false\"")
$([ "$INSTALL_KAFKA" = true ] && echo "    - name: LAKERUNNER_FLY_BROKERS" || echo "    # - name: LAKERUNNER_FLY_BROKERS")
$([ "$INSTALL_KAFKA" = true ] && echo "      value: \"kafka.$NAMESPACE.svc.cluster.local:9092\"" || echo "    #   value: \"$KAFKA_BOOTSTRAP_SERVERS\"")

# PubSub configuration
pubsub:
  HTTP:
    enabled: $([ "$USE_SQS" = true ] && echo "false" || echo "true")
    replicas: 1  # Reduce for local development

  SQS:
    enabled: $([ "$USE_SQS" = true ] && echo "true" || echo "false")
    $([ "$USE_SQS" = true ] && echo "queueURL: \"$SQS_QUEUE_URL\"" || echo "# queueURL: \"\"")
    $([ "$USE_SQS" = true ] && echo "region: \"$SQS_REGION\"" || echo "# region: \"\"")

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
  replicas: 1  # Reduce for local development
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
  replicas: 1  # Reduce for local development
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
  replicas: 1  # Reduce for local development
  resources:
    requests:
      cpu: 500m
      memory: 200Mi
    limits:
      cpu: 1000m
      memory: 400Mi
  autoscaling:
    enabled: false  # Disable autoscaling for local development

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

queryApiV2:
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

queryWorkerV2:
  enabled: true
  replicas: 2 # Pin for local development
  resources:
    requests:
      cpu: 500m
      memory: 2Gi
    limits:
      cpu: 500m
      memory: 2Gi

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
    - "https://github.com/cardinalhq/cardinalhq-lakerunner-datasource/releases/download/v1.2.0-rc.3/cardinalhq-lakerunner-datasource.zip;cardinalhq-lakerunner-datasource"
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

# Function to install LakeRunner
install_lakerunner() {
    print_status "Installing LakeRunner in namespace: $NAMESPACE"
    
    helm install lakerunner oci://public.ecr.aws/cardinalhq.io/lakerunner \
        --version 0.8.1 \
        --values generated/values-local.yaml \
        --namespace $NAMESPACE
    print_success "LakeRunner installed successfully in namespace: $NAMESPACE"
}

# Function to wait for services to be ready
wait_for_services() {
    print_status "Waiting for LakeRunner services to be ready in namespace: $NAMESPACE"
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

setup_port_forwarding() {
    print_status "Setting up port forwarding for LakeRunner services..."

    # Kill any existing port forwarding processes
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "kubectl port-forward.*minio.*9001" 2>/dev/null || true
        pkill -f "kubectl port-forward.*lakerunner-query-api-v2.*8080" 2>/dev/null || true
        pkill -f "kubectl port-forward.*lakerunner-grafana.*3000" 2>/dev/null || true
    else
        # Fallback for systems without pkill (like macOS)
        ps aux | grep "kubectl port-forward.*minio.*9001" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
        ps aux | grep "kubectl port-forward.*lakerunner-query-api-v2.*8080" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
        ps aux | grep "kubectl port-forward.*lakerunner-grafana.*3000" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
    fi
    sleep 1

    # Setup MinIO port forwarding if using local MinIO
    if [ "$INSTALL_MINIO" = true ]; then
        print_status "Setting up port forwarding for MinIO Console..."
        
        # Start port forwarding in background
        print_status "Starting MinIO port forwarding..."
        kubectl -n "$NAMESPACE" port-forward svc/minio 9000:9000 > /dev/null 2>&1 &
        sleep 2
        kubectl -n "$NAMESPACE" port-forward svc/minio-console 9001:9001 > /dev/null 2>&1 &
        
    else
        print_status "Skipping MinIO port forwarding (using external S3 storage)"
    fi

    print_status "Starting LakeRunner Query API port forwarding..."
    kubectl -n "$NAMESPACE" port-forward svc/lakerunner-query-api-v2 8080:8080 > /dev/null 2>&1 &
    sleep 2

    # Start Grafana port forwarding
    print_status "Starting Grafana port forwarding..."
    kubectl -n "$NAMESPACE" port-forward svc/lakerunner-grafana 3000:3000 > /dev/null 2>&1 &
}

display_connection_info() {
    print_success "LakeRunner installation completed successfully!"
    echo
    echo "=== Connection Information ==="
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
        echo "  Cardinal Dashboard: https://app.cardinalhq.io"
    else
        echo "  Cardinal Telemetry: Disabled"
    fi
    echo
    
    # Get MinIO credentials
    MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
    MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
    
    if [ "$INSTALL_MINIO" = true ]; then
        echo "MinIO Console:"
        echo "  URL: http://localhost:9001"
        echo "  Access Key: $MINIO_ACCESS_KEY"
        echo "  Secret Key: $MINIO_SECRET_KEY"
        echo
    else
        echo "S3 Storage:"
        echo "  Bucket: $S3_BUCKET"
        echo "  Region: $S3_REGION"
        echo
    fi
    
    if [ "$INSTALL_POSTGRES" = true ]; then
        echo "PostgreSQL:"
        echo "  Host: postgres-postgresql.$NAMESPACE.svc.cluster.local"
        echo "  Port: 5432"
        echo "  Database: lakerunner"
        echo "  Username: lakerunner"
        echo "  Password: lakerunnerpass"
        echo
    else
        echo "PostgreSQL:"
        echo "  Host: $POSTGRES_HOST"
        echo "  Port: $POSTGRES_PORT"
        echo "  Database: $POSTGRES_DB"
        echo "  Username: $POSTGRES_USER"
        echo
    fi
    
    if [ "$INSTALL_KAFKA" = true ]; then
        echo "Kafka:"
        echo "  Bootstrap Servers: kafka.$NAMESPACE.svc.cluster.local:9092"
        echo "  Protocol: PLAINTEXT (no authentication)"
        echo
    else
        echo "Kafka:"
        echo "  Bootstrap Servers: $KAFKA_BOOTSTRAP_SERVERS"
        if [ -n "$KAFKA_USERNAME" ]; then
            echo "  Username: $KAFKA_USERNAME"
        fi
        echo
    fi
    
    if [ "$USE_SQS" = true ]; then
        echo "LakeRunner PubSub SQS Configuration:"
        echo "  Queue URL: $SQS_QUEUE_URL"
        echo "  Region: $SQS_REGION"
        echo
    else
            echo "LakeRunner PubSub HTTP Endpoint:"
    echo "  URL: http://lakerunner-pubsub-http.$NAMESPACE.svc.cluster.local:8080/"
    echo
    
    echo "Grafana Dashboard:"
    echo "  URL: http://localhost:3000"
    echo "  Username: admin"
    echo "  Password: admin"
    echo "  Datasource: Cardinal (pre-configured)"
    echo
    fi
    
    echo "=== Next Steps ==="
    if [ "$INSTALL_MINIO" = true ]; then
        echo "1. Access MinIO Console at http://localhost:9001"
        echo "2. Create a bucket named 'lakerunner'"
    else
        echo "1. Ensure your S3 bucket '$S3_BUCKET' exists and is accessible"
    fi
    
    if [ "$USE_SQS" = true ]; then
        echo "2. Configure S3 bucket notifications to send events to your SQS queue:"
        echo "   - Queue ARN: arn:aws:sqs:$SQS_REGION:$(echo $SQS_QUEUE_URL | cut -d'/' -f4):$(echo $SQS_QUEUE_URL | cut -d'/' -f5)"
        echo "   - Event types: s3:ObjectCreated:*"
        echo "3. Configure SQS queue policy to allow S3 to send messages"
        echo "4. Ensure IAM permissions for LakeRunner to read from SQS"
    else
        echo "2. Configure event notifications in your S3-compatible storage:"
        echo "   - Add event notification pointing to:"
        echo "     http://lakerunner-pubsub-http.$NAMESPACE.svc.cluster.local:8080/"
        echo "3. The event notification ARN should appear in the bucket configuration"
    fi
    echo
    
    if [ "$ENABLE_CARDINAL_TELEMETRY" = true ]; then
        echo "4. Cardinal Telemetry is enabled and sending data to Cardinal"
        echo "   You can view your telemetry data at: https://app.cardinalhq.io"
    else
        echo "4. Cardinal Telemetry is disabled"
        echo "   To enable later, update values-local.yaml and upgrade the release"
    fi
    echo
    echo "For detailed setup instructions, visit: https://github.com/cardinalhq/lakerunner"

    if [ "$INSTALL_OTEL_DEMO" = true ]; then
        echo
        echo "=== OpenTelemetry Demo Apps ==="
        echo "Demo applications have been installed in the 'otel-demo' namespace."
        echo "These apps will generate sample telemetry data that will be:"
        echo "1. Collected by the OpenTelemetry Collector"
        echo "2. Exported to MinIO S3 storage"
        echo "3. Processed by LakeRunner"
        echo "4. Available in Grafana dashboard"
        echo
        echo "To access the demo applications:"
        echo "  kubectl port-forward svc/otel-demo-frontend 8080:8080 -n otel-demo"
        echo "  Then visit: http://localhost:8080"
        echo
        echo "The demo apps will continuously generate logs, metrics, and traces"
        echo "that will flow through LakeRunner for processing and analysis."
        echo
    fi

}

ask_install_otel_demo() {
    echo
    echo "=== OpenTelemetry Demo Apps ==="
    echo "Would you like to install the OpenTelemetry demo applications?"
    echo "This will deploy a sample e-commerce application that generates"
    echo "logs, metrics, and traces to demonstrate LakeRunner in action."
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
          s3_force_path_style: true
          disable_ssl: true
      awss3/logs:
        marshaler: otlp_proto
        s3uploader:
          s3_bucket: "lakerunner"
          s3_prefix: "otel-raw/$ORG_ID/lakerunner"
          endpoint: http://minio.$NAMESPACE.svc.cluster.local:9000
          s3_force_path_style: true
          disable_ssl: true
      awss3/traces:
        marshaler: otlp_proto
        s3uploader:
          s3_bucket: "lakerunner"
          s3_prefix: "otel-raw/$ORG_ID/lakerunner"
          endpoint: http://minio.$NAMESPACE.svc.cluster.local:9000
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
        print_status "Setting up MinIO webhooks for LakeRunner event notifications..."
        
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
        
        print_success "MinIO webhooks configured successfully for LakeRunner event notifications"
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
        helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
        helm repo update >/dev/null  2>&1

        helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
            --namespace otel-demo \
            --values generated/otel-demo-values.yaml >/dev/null 2>&1

        print_success "OpenTelemetry demo apps installed successfully"
        echo
        echo "=== OpenTelemetry Demo Apps ==="
        echo "Demo applications have been installed in the 'otel-demo' namespace."
        echo "These apps will generate sample telemetry data that will be:"
        echo "1. Collected by the OpenTelemetry Collector"
        echo "2. Exported to MinIO S3 storage"
        echo "3. Processed by LakeRunner"
        echo "4. Available in Grafana dashboard"
        echo
        echo "To access the demo applications, run the following:"
        echo " kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=frontend-proxy -n otel-demo --timeout=300s "
        echo " kubectl port-forward svc/frontend-proxy 8080:8080 -n otel-demo "
        echo "Then visit http://localhost:8080"
        echo "The demo apps will continuously generate logs, metrics, and traces"
        echo "that will flow through LakeRunner for processing and analysis."
        echo
    else
        print_status "Skipping OpenTelemetry demo apps installation"
    fi
}

main() {
    echo "=========================================="
    echo "    LakeRunner Installation Script"
    echo "=========================================="
    echo

    check_prerequisites
    
    # Get all user preferences first
    get_namespace
    get_infrastructure_preferences
    get_telemetry_preferences
    get_lakerunner_credentials
    ask_install_otel_demo

    # Display configuration summary
    display_configuration_summary

    # Confirm installation
    confirm_installation

    # Start installation process
    print_status "Starting installation process..."

    # Ensure namespace exists before installing anything
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE" >/dev/null 2>&1
    
    install_minio
    install_postgresql
    install_kafka
    setup_kafka_topics
    
    generate_values_file
    
    install_lakerunner
    
    wait_for_services
    
    setup_port_forwarding

    # Setup MinIO webhooks for LakeRunner event notifications (required for LakeRunner to function)
    setup_minio_webhooks

    generate_otel_demo_values

    install_otel_demo

    display_connection_info
}

main "$@" 
