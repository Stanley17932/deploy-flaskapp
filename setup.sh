#!/bin/bash

# Text Analyzer Application Setup Script
# This script helps set up the GCP environment and deploy the application

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

print_status "Starting Text Analyzer Application Setup..."

# Check prerequisites
print_status "Checking prerequisites..."

if ! command_exists "gcloud"; then
    print_error "gcloud CLI is not installed. Please install it first."
    echo "Visit: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

if ! command_exists "terraform"; then
    print_error "Terraform is not installed. Please install it first."
    echo "Visit: https://developer.hashicorp.com/terraform/downloads"
    exit 1
fi

if ! command_exists "docker"; then
    print_error "Docker is not installed. Please install it first."
    echo "Visit: https://docs.docker.com/get-docker/"
    exit 1
fi

print_success "All prerequisites are installed."

# Check if user is authenticated with gcloud
print_status "Checking gcloud authentication..."
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q "@"; then
    print_warning "No active gcloud authentication found."
    print_status "Please authenticate with gcloud:"
    gcloud auth login
    gcloud auth application-default login
fi

# List available projects
print_status "Available GCP projects:"
gcloud projects list --format="table(projectId,name,projectNumber)"

# Prompt for project selection
echo
read -p "Enter your GCP Project ID: " PROJECT_ID

if [ -z "$PROJECT_ID" ]; then
    print_error "Project ID cannot be empty."
    exit 1
fi

# Set the project
print_status "Setting GCP project to: $PROJECT_ID"
gcloud config set project "$PROJECT_ID"

# Verify project exists and user has access
if ! gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
    print_error "Cannot access project '$PROJECT_ID'. Please check the project ID and your permissions."
    exit 1
fi

print_success "Project set successfully."

# Prompt for region
echo
read -p "Enter your preferred GCP region (default: us-central1): " REGION
REGION=${REGION:-us-central1}

# Create terraform.tfvars file
print_status "Creating terraform.tfvars file..."
cat > terraform/terraform.tfvars << EOF
project_id              = "$PROJECT_ID"
region                  = "$REGION"
app_name               = "text-analyzer"
artifact_registry_repo = "deploy-flaskapp"
image_tag              = "latest"
EOF

print_success "terraform.tfvars created successfully."

# Enable billing (if needed)
print_status "Checking if billing is enabled for the project..."
BILLING_ACCOUNT=$(gcloud beta billing projects describe "$PROJECT_ID" --format="value(billingAccountName)" 2>/dev/null | cut -d'/' -f2)

if [ -z "$BILLING_ACCOUNT" ]; then
    print_warning "Billing is not enabled for this project."
    print_status "Available billing accounts:"
    gcloud beta billing accounts list
    echo
    read -p "Enter billing account ID to link (or press Enter to skip): " BILLING_ID
    
    if [ ! -z "$BILLING_ID" ]; then
        print_status "Linking billing account..."
        gcloud beta billing projects link "$PROJECT_ID" --billing-account="$BILLING_ID"
        print_success "Billing account linked successfully."
    else
        print_warning "Skipping billing setup. You may need to enable billing manually."
    fi
else
    print_success "Billing is already enabled."
fi

# Initialize Terraform
print_status "Initializing Terraform..."
cd terraform
terraform init
print_success "Terraform initialized successfully."

# Plan Terraform deployment
print_status "Creating Terraform plan..."
terraform plan
print_success "Terraform plan created successfully."

echo
print_success "Setup completed successfully!"
echo
print_status "Next steps:"
echo "1. Review the Terraform plan above"
echo "2. Run 'terraform apply' in the terraform/ directory to deploy infrastructure"
echo "3. Build and push your Docker image:"
echo "   docker build -t $REGION-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp/text-analyzer:latest ."
echo "   docker push $REGION-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp/text-analyzer:latest"
echo "4. Update the image_tag in terraform.tfvars and run 'terraform apply' again"
echo
print_status "For GitHub Actions CI/CD, make sure to set up the following secrets:"
echo "- GCP_PROJECT_ID: $PROJECT_ID"
echo "- GCP_SA_KEY: Service account key JSON (create a service account with necessary permissions)"