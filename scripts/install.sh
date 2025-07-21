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
            --set persistence.enabled=false \
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
        
        kubectl -n "$NAMESPACE" patch service minio -p '{"spec":{"ports":[{"name":"console","port":9001,"protocol":"TCP","targetPort":9001}]}}'
        
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
            --set persistence.enabled=false
        
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
      endpoint: "$([ "$INSTALL_MINIO" = true ] && echo "http://minio.$NAMESPACE.svc.cluster.local:9000" || echo "$S3_ENDPOINT")"

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

# PubSub configuration
pubsub:
  HTTP:
    enabled: $([ "$USE_SQS" = true ] && echo "false" || echo "true")
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
  enabled: true
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
  enabled: true
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
  enabled: true
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
  enabled: true
  replicas: 1
  resources:
    requests:
      cpu: 1000m
      memory: 500Mi
    limits:
      cpu: 2000m
      memory: 1Gi
  autoscaling:
    enabled: false

rollupMetrics:
  enabled: true
  replicas: 1
  resources:
    requests:
      cpu: 500m
      memory: 500Mi
    limits:
      cpu: 1000m
      memory: 1Gi
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
  minWorkers: 1
  maxWorkers: 2
  resources:
    requests:
      cpu: 250m
      memory: 512Mi
    limits:
      cpu: 500m
      memory: 1Gi

queryWorker:
  enabled: true
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 1000m
      memory: 2Gi
EOF

    print_success "values-local.yaml generated successfully"
}

# Function to install LakeRunner
install_lakerunner() {
    print_status "Installing LakeRunner in namespace: $NAMESPACE"
    
    helm install lakerunner oci://public.ecr.aws/cardinalhq.io/lakerunner \
			  --version 0.2.22 \
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
    
    # Wait for query-api service
    print_status "Waiting for query-api service..."
    kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=lakerunner,app.kubernetes.io/component=query-api -n "$NAMESPACE" --timeout=300s
    
    print_success "All services are ready in namespace: $NAMESPACE"
}

# Function to setup port forwarding
setup_port_forwarding() {
    if [ "$INSTALL_MINIO" = true ]; then
        print_status "Setting up port forwarding for MinIO Console..."
        
            # Kill any existing port forwarding processes
    if command -v pkill >/dev/null 2>&1; then
        pkill -f "kubectl port-forward.*minio.*9001" 2>/dev/null || true
    else
        # Fallback for systems without pkill (like macOS)
        ps aux | grep "kubectl port-forward.*minio.*9001" | grep -v grep | awk '{print $2}' | xargs kill 2>/dev/null || true
    fi
    sleep 1
        
        # Start port forwarding in background
        print_status "Starting MinIO port forwarding..."
        kubectl -n "$NAMESPACE" port-forward svc/minio 9000:9000 > /dev/null 2>&1 &
        kubectl -n "$NAMESPACE" port-forward svc/minio 9001:9001 > /dev/null 2>&1 &
        PF_PID=$!
        
        # Wait for port forwarding to start
        print_status "Waiting for port forwarding to be ready..."
        for i in {1..10}; do
            if curl -s http://localhost:9001 > /dev/null 2>&1; then
                print_success "MinIO Console port forwarding started successfully"
                print_success "Access MinIO Console at: http://localhost:9001"
                return 0
            fi
            sleep 1
        done
        
        # If we get here, port forwarding failed
        print_warning "Port forwarding may not be working. You can manually run:"
        echo "  kubectl port-forward svc/minio 9001:9001"
        echo "  Then access: http://localhost:9001"
    else
        print_status "Skipping MinIO port forwarding (using external S3 storage)"
    fi
}

# Function to display connection information
display_connection_info() {
    print_success "LakeRunner installation completed successfully!"
    echo
    echo "=== Connection Information ==="
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
    echo "For detailed setup instructions, visit: https://github.com/cardinalhq/lakerunner"

}

# Main installation function
main() {
    echo "=========================================="
    echo "    LakeRunner Installation Script"
    echo "=========================================="
    echo
    
    # Check prerequisites
    check_prerequisites
    
    # Get namespace configuration
    get_namespace

    # Ensure namespace exists before installing anything
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || kubectl create namespace "$NAMESPACE"
    
    # Get infrastructure preferences
    get_infrastructure_preferences
    
    # Install dependencies
    install_minio
    install_postgresql
    
    # Generate configuration
    generate_values_file
    
    # Install LakeRunner
    install_lakerunner
    
    # Wait for services
    wait_for_services
    
    # Setup port forwarding
    setup_port_forwarding
    
    # Display connection information
    display_connection_info
}

# Run main function
main "$@" 
