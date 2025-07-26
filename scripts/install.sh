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
        get_input "Enter S3 endpoint URL" "" "S3_ENDPOINT"
        get_input "Enter S3 access key" "" "S3_ACCESS_KEY"
        get_input "Enter S3 secret key" "" "S3_SECRET_KEY"
        get_input "Enter S3 region" "us-east-1" "S3_REGION"
        get_input "Enter S3 bucket name" "lakerunner" "S3_BUCKET"
        

    fi
    
    echo
    echo "=== SQS Configuration (Optional) ==="
    if [ "$INSTALL_MINIO" = true ]; then
        echo "Note: SQS is not needed when using local MinIO. HTTP webhook is sufficient."
        echo "SQS is recommended for production AWS S3 deployments."
    else
        echo "Note: For external S3 storage, you can use either:"
        echo "1. HTTP webhook (simpler, works with any S3-compatible storage)"
        echo "2. SQS queue (recommended for production AWS S3)"
    fi
    echo
    
    get_input "Do you want to configure SQS for event notifications? (y/N)" "N" "USE_SQS"
    if [[ "$USE_SQS" =~ ^[Yy]$ ]]; then
        USE_SQS=true
        print_status "Will configure SQS for event notifications"
        
        get_input "Enter SQS queue URL" "" "SQS_QUEUE_URL"
        get_input "Enter SQS region" "$([ "$INSTALL_MINIO" = true ] && echo "us-east-1" || echo "$S3_REGION")" "SQS_REGION"
        get_input "Enter IAM role ARN (optional, press Enter to skip)" "" "SQS_ROLE_ARN"
        
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
}

get_telemetry_preferences() {
    echo
    echo "=== Telemetry Configuration ==="
    echo "LakeRunner can process logs, metrics, or both."
    echo "Choose which telemetry types you want to enable:"
    echo "1. Logs only"
    echo "2. Metrics only"
    echo "3. Both logs and metrics (default)"
    echo
    
    get_input "Select telemetry type (1/2/3)" "3" "TELEMETRY_CHOICE"
    
    case "$TELEMETRY_CHOICE" in
        1)
            ENABLE_LOGS=true
            ENABLE_METRICS=false
            print_status "Will enable logs only"
            ;;
        2)
            ENABLE_LOGS=false
            ENABLE_METRICS=true
            print_status "Will enable metrics only"
            ;;
        3|"")
            ENABLE_LOGS=true
            ENABLE_METRICS=true
            print_status "Will enable both logs and metrics"
            ;;
        *)
            print_error "Invalid choice. Defaulting to both logs and metrics."
            ENABLE_LOGS=true
            ENABLE_METRICS=true
            ;;
    esac
    
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

get_cardinal_api_key() {
    print_status "To enable Cardinal telemetry, you need to create a Cardinal API key."
    print_status "Please follow these steps:"
    echo
    print_status "1. Open your browser and go to: ${BLUE}https://app.cardinal.io${NC}"
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
        
        helm repo add minio https://charts.min.io/ 2>/dev/null || true
        helm repo update
        
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
            --set service.ports[1].targetPort=9001
        
        print_status "Waiting for MinIO to be ready..."
        kubectl wait --for=condition=ready pod -l app=minio -n "$NAMESPACE" --timeout=300s
                
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
        helm repo update
        
        helm install postgres bitnami/postgresql \
            --namespace "$NAMESPACE" \
            --set auth.username=lakerunner \
            --set auth.password=lakerunnerpass \
            --set auth.database=lakerunner \
            --set persistence.enabled=true \
            --set persistence.size=8Gi
        
        print_status "Waiting for PostgreSQL to be ready..."
        kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n "$NAMESPACE" --timeout=300s
        
        print_success "PostgreSQL installed successfully"
    else
        print_status "Skipping PostgreSQL installation (using existing database)"
    fi
}

generate_values_file() {
    print_status "Generating values-local.yaml..."
    
    get_input "Enter organization ID (or press Enter for default)" "65928f26-224b-4acb-8e57-9ee628164694" "ORG_ID"
    get_input "Enter API key (or press Enter for default)" "test-key" "API_KEY"
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
    
    cat > values-local.yaml << EOF
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

# Storage profiles
storageProfiles:
  source: "config"  # Use config file for storage profiles
  create: true
  yaml:
    - organization_id: "$ORG_ID"
      instance_num: 1
      collector_name: "chq-saas"
      cloud_provider: "$([ "$INSTALL_MINIO" = true ] && echo "minio" || echo "aws")"
      region: "$([ "$INSTALL_MINIO" = true ] && echo "local" || echo "$S3_REGION")"
      bucket: "$([ "$INSTALL_MINIO" = true ] && echo "lakerunner" || echo "$S3_BUCKET")"
      use_path_style: true
      use_ssl: "$([ "$INSTALL_MINIO" = true ] && echo false || echo true)"
      endpoint: "$([ "$INSTALL_MINIO" = true ] && echo "minio.$NAMESPACE.svc.cluster.local:9000" || echo "$S3_ENDPOINT")"

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

# AWS/S3 credentials configuration
aws:
  region: "$([ "$INSTALL_MINIO" = true ] && echo "us-east-1" || echo "$S3_REGION")"  # This doesn't matter for MinIO but is required
  create: true  # Create the secret with credentials
  secretName: "aws-credentials"
  inject: true
  accessKeyId: "$MINIO_ACCESS_KEY"
  secretAccessKey: "$MINIO_SECRET_KEY"

# Global OpenTelemetry configuration for Cardinal
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "global:" || echo "# global:")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "  env:" || echo "  # env:")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    # Enable OpenTelemetry logs, metrics, and traces for all components" || echo "    # Enable OpenTelemetry logs, metrics, and traces for all components")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: ENABLE_OTLP_TELEMETRY" || echo "    # - name: ENABLE_OTLP_TELEMETRY")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"true\"" || echo "      #   value: \"true\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    # OpenTelemetry configuration for Cardinal" || echo "    # OpenTelemetry configuration for Cardinal")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: OTEL_TRACES_EXPORTER" || echo "    # - name: OTEL_TRACES_EXPORTER")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"otlp\"" || echo "      #   value: \"otlp\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: OTEL_METRICS_EXPORTER" || echo "    # - name: OTEL_METRICS_EXPORTER")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"otlp\"" || echo "      #   value: \"otlp\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: OTEL_LOGS_EXPORTER" || echo "    # - name: OTEL_LOGS_EXPORTER")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"otlp\"" || echo "      #   value: \"otlp\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: OTEL_EXPORTER_OTLP_ENDPOINT" || echo "    # - name: OTEL_EXPORTER_OTLP_ENDPOINT")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"https://otelhttp.intake.us-east-2.aws.cardinalhq.io\"" || echo "      #   value: \"https://otelhttp.intake.us-east-2.aws.cardinalhq.io\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: OTEL_EXPORTER_OTLP_HEADERS" || echo "    # - name: OTEL_EXPORTER_OTLP_HEADERS")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"x-cardinalhq-api-key=$CARDINAL_API_KEY\"" || echo "      #   value: \"x-cardinalhq-api-key=\"")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "    - name: OTEL_SERVICE_NAME" || echo "    # - name: OTEL_SERVICE_NAME")
$([ "$ENABLE_CARDINAL_TELEMETRY" = true ] && echo "      value: \"lakerunner\"" || echo "      #   value: \"lakerunner\"")

# PubSub configuration
pubsub:
  HTTP:
    enabled: $([ "$USE_SQS" = true ] && echo "false" || echo "true")
    replicas: 1  # Reduce for local development

  SQS:
    enabled: $([ "$USE_SQS" = true ] && echo "true" || echo "false")
    $([ "$USE_SQS" = true ] && echo "queueURL: \"$SQS_QUEUE_URL\"" || echo "# queueURL: \"\"")
    $([ "$USE_SQS" = true ] && echo "region: \"$SQS_REGION\"" || echo "# region: \"\"")
    $([ "$USE_SQS" = true ] && [ -n "$SQS_ROLE_ARN" ] && echo "roleARN: \"$SQS_ROLE_ARN\"" || echo "# roleARN: \"\"")

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
  minWorkers: 2 # Pin for local development
  maxWorkers: 2 # Pin for local development
  resources:
    requests:
      cpu: 1000m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 1Gi

queryWorker:
  enabled: true
  initialReplicas: 2 # Pin for local development
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
    - "https://github.com/cardinalhq/cardinalhq-lakerunner-datasource/raw/refs/heads/main/cardinalhq-lakerunner-datasource.zip;cardinalhq-lakerunner-datasource"
  datasources:
    datasources.yaml:
      apiVersion: 1
      datasources:
        - name: Cardinal
          type: cardinalhq-lakerunner-datasource
          access: proxy
          isDefault: true
          editable: true
          jsonData:
            customPath: "http://lakerunner-query-api.$NAMESPACE.svc.cluster.local:7101"
          secureJsonData:
            apiKey: "$API_KEY"
EOF

    print_success "values-local.yaml generated successfully"
}

# Function to install LakeRunner
install_lakerunner() {
    print_status "Installing LakeRunner in namespace: $NAMESPACE"
    
    helm install lakerunner oci://public.ecr.aws/cardinalhq.io/lakerunner \
        --version 0.2.27 \
        --values values-local.yaml \
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
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=lakerunner,app.kubernetes.io/component=query-api -n "$NAMESPACE" --timeout=300s
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=lakerunner,app.kubernetes.io/component=grafana -n "$NAMESPACE" --timeout=300s || true
    print_success "All services are ready in namespace: $NAMESPACE"
}

setup_port_forwarding() {
    print_status "Setting up port forwarding for LakeRunner services..."

    # Kill any existing port forwarding processes
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "kubectl port-forward.*minio.*9001" 2>/dev/null || true
        pkill -f "kubectl port-forward.*lakerunner-query-api.*7101" 2>/dev/null || true
        pkill -f "kubectl port-forward.*lakerunner-grafana.*3000" 2>/dev/null || true
    else
        # Fallback for systems without pkill (like macOS)
        ps aux | grep "kubectl port-forward.*minio.*9001" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
        ps aux | grep "kubectl port-forward.*lakerunner-query-api.*7101" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
        ps aux | grep "kubectl port-forward.*lakerunner-grafana.*3000" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
    fi
    sleep 1

    # Setup MinIO port forwarding if using local MinIO
    if [ "$INSTALL_MINIO" = true ]; then
        print_status "Setting up port forwarding for MinIO Console..."
        
        # Start port forwarding in background
        print_status "Starting MinIO port forwarding..."
        kubectl -n "$NAMESPACE" port-forward svc/minio 9000:9000 > /dev/null 2>&1 &
        kubectl -n "$NAMESPACE" port-forward svc/minio 9001:9001 > /dev/null 2>&1 &
        
        # Wait for port forwarding to start
        print_status "Waiting for port forwarding to be ready..."
        for i in {1..10}; do
            if curl -s http://localhost:9001 > /dev/null 2>&1; then
                print_success "MinIO Console port forwarding started successfully"
                print_success "Access MinIO Console at: http://localhost:9001"
                break
            fi
            sleep 1
        done
        
        # If we get here, port forwarding failed
        if [ $i -eq 10 ]; then
            print_warning "MinIO port forwarding may not be working. You can manually run:"
            echo "  kubectl port-forward svc/minio 9001:9001"
            echo "  Then access: http://localhost:9001"
        fi
    else
        print_status "Skipping MinIO port forwarding (using external S3 storage)"
    fi

    print_status "Starting LakeRunner Query API port forwarding..."
    kubectl -n "$NAMESPACE" port-forward svc/lakerunner-query-api 7101:7101 > /dev/null 2>&1 &

    # Start Grafana port forwarding
    print_status "Starting Grafana port forwarding..."
    kubectl -n "$NAMESPACE" port-forward svc/lakerunner-grafana 3000:3000 > /dev/null 2>&1 &

    # Wait for LakeRunner services port forwarding to start
    print_status "Waiting for LakeRunner services port forwarding to be ready..."
    for i in {1..20}; do
        if curl -s http://localhost:7101 > /dev/null 2>&1 && curl -s http://localhost:3000 > /dev/null 2>&1; then
            print_success "LakeRunner services port forwarding started successfully"
            print_success "Access LakeRunner Query API at: http://localhost:7101"
            print_success "Access Grafana at: http://localhost:3000"
            return 0
        fi
        sleep 1
    done

    if [ $i -eq 10 ]; then
      # If we get here, port forwarding failed
      print_warning "Some port forwarding may not be working. You can manually run:"
      echo "  kubectl -n $NAMESPACE port-forward svc/lakerunner-query-api 7101:7101"
      echo "  kubectl -n $NAMESPACE port-forward svc/lakerunner-grafana 3000:3000"
    fi
}

display_connection_info() {
    print_success "LakeRunner installation completed successfully!"
    echo
    echo "=== Connection Information ==="
    echo
    
    echo "Telemetry Configuration:"
    if [ "$ENABLE_LOGS" = true ] && [ "$ENABLE_METRICS" = true ]; then
        echo "  Enabled: Logs and Metrics"
    elif [ "$ENABLE_LOGS" = true ]; then
        echo "  Enabled: Logs only"
    elif [ "$ENABLE_METRICS" = true ]; then
        echo "  Enabled: Metrics only"
    fi
    
    if [ "$ENABLE_CARDINAL_TELEMETRY" = true ]; then
        echo "  Cardinal Telemetry: Enabled"
        echo "  Cardinal Dashboard: https://app.test.cardinal.io"
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
        echo "  Endpoint: $S3_ENDPOINT"
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
    
    if [ "$USE_SQS" = true ]; then
        echo "LakeRunner PubSub SQS Configuration:"
        echo "  Queue URL: $SQS_QUEUE_URL"
        echo "  Region: $SQS_REGION"
        if [ -n "$SQS_ROLE_ARN" ]; then
            echo "  Role ARN: $SQS_ROLE_ARN"
        fi
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
        echo "   You can view your telemetry data at: https://app.test.cardinal.io"
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

    get_input "Install OTEL demo apps? (y/N)" "N" "INSTALL_OTEL_DEMO"

    if [[ "$INSTALL_OTEL_DEMO" =~ ^[Yy]$ ]]; then
        INSTALL_OTEL_DEMO=true
        print_status "Will install OpenTelemetry demo apps"
    else
        INSTALL_OTEL_DEMO=false
        print_status "Skipping OpenTelemetry demo apps installation"
    fi
}

generate_otel_demo_values() {
    print_status "Generating OTEL demo values file..."

    # Get MinIO credentials
    MINIO_ACCESS_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootUser}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")
    MINIO_SECRET_KEY=$(kubectl get secret minio -n "$NAMESPACE" -o jsonpath="{.data.rootPassword}" 2>/dev/null | base64 --decode 2>/dev/null || echo "minioadmin")

    cat > otel-demo-values.yaml << EOF
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
        value: http://$(OTEL_COLLECTOR_NAME):4317
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
          s3_prefix: "metrics-raw"
          endpoint: http://minio.$NAMESPACE.svc.cluster.local:9000
          s3_force_path_style: true
          disable_ssl: true
      awss3/logs:
        marshaler: otlp_proto
        s3uploader:
          s3_bucket: "lakerunner"
          s3_prefix: "logs-raw"
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
          exporters: [spanmetrics]
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

    print_success "OTEL demo values file generated successfully"
}

install_otel_demo() {
    if [ "$INSTALL_OTEL_DEMO" = true ]; then
        print_status "Installing OpenTelemetry demo apps..."

        # Check if lakerunner bucket exists (required for OTEL demo to work)
        if [ "$INSTALL_MINIO" = true ]; then
            print_status "Checking if lakerunner bucket exists in MinIO..."
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
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc admin config set minio notify_webhook:create_object endpoint="http://lakerunner-pubsub-http.$NAMESPACE.svc.cluster.local:8080/" >/dev/null 2>&1
            echo "Created webhook to pubsub, restarting minio pod to apply configuration"
            kubectl rollout restart deployment/minio -n "$NAMESPACE"
            sleep 10
            echo "slept 10 seconds"
            echo $S3_BUCKET
            # Re-setup mc alias after pod restart
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc alias set minio http://localhost:9000 $MINIO_ACCESS_KEY $MINIO_SECRET_KEY >/dev/null 2>&1
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "logs-raw"
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "metrics-raw" >/dev/null 2>&1
            kubectl exec -n "$NAMESPACE" deployment/minio -- mc event add --event "put" minio/$S3_BUCKET arn:minio:sqs::create_object:webhook --prefix "otel-raw" >/dev/null 2>&1
        else
            print_warning "Using external S3 storage. Please ensure the 'lakerunner' bucket exists."
            echo "The OTEL demo apps will fail if the bucket doesn't exist."
            read -p "Press Enter to continue..."
        fi

        kubectl get namespace "otel-demo" >/dev/null 2>&1 || kubectl create namespace "otel-demo"

        # Add OpenTelemetry Helm repository
        helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts 2>/dev/null || true
        helm repo update

        helm upgrade --install otel-demo open-telemetry/opentelemetry-demo \
            --namespace otel-demo \
            --values otel-demo-values.yaml

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
        echo "To access the demo applications:"
        echo "  kubectl port-forward svc/otel-demo-frontend 8080:8080 -n otel-demo"
        echo "  Then visit: http://localhost:8080"
        echo
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
    
    get_namespace

    # Ensure namespace exists before installing anything
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
    
    get_infrastructure_preferences
    
    get_telemetry_preferences
    
    install_minio
    install_postgresql
    
    generate_values_file
    
    install_lakerunner
    
    wait_for_services
    
    setup_port_forwarding
    
    ask_install_otel_demo

    generate_otel_demo_values

    install_otel_demo

    display_connection_info
}

main "$@" 
