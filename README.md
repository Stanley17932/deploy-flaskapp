# Text Analyzer - Cloud Run Deployment

A Flask-based text analysis service deployed on Google Cloud Run with automated CI/CD pipeline using GitHub Actions and Terraform infrastructure as code.

## 📋 Table of Contents

- [Architecture Overview](#architecture-overview)
- [Design Decisions](#design-decisions)
- [Security Implementation](#security-implementation)
- [Setup and Deployment Instructions](#setup-and-deployment-instructions)
- [CI/CD Pipeline](#cicd-pipeline)
- [Testing the Service](#testing-the-service)
- [Monitoring and Troubleshooting](#monitoring-and-troubleshooting)

## 🏗️ Architecture Overview

```
GitHub Repository
       │
       ▼
┌─────────────────┐    Push to main    ┌─────────────────┐
│                 │───────────────────▶│ GitHub Actions  │
│   Source Code   │                    │    Workflow     │
│   - Flask App   │                    │                 │
│   - Dockerfile  │                    │ 1. Lint & Test  │
│   - Terraform   │                    │ 2. Build Image  │
└─────────────────┘                    │ 3. Push to GAR  │
                                       │ 4. Deploy Infra │
                                       └─────────────────┘
                                              │
                                              ▼
┌─────────────────┐                    ┌─────────────────┐
│ Artifact        │◀───Docker Push────| Docker Build    |
│ Registry        │                    │ & Authentication│
│ (Private Repo)  │                    └─────────────────┘
└─────────────────┘
       │
       │ Pull Image
       ▼
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Run                         │
│                                                             │
│  ┌───────────────┐    ┌─────────────────┐   ┌────────────┐  │
│  │ Load Balancer │────│ Flask Container │───│ Health     │  │
│  │ (HTTPS)       │    │ - Non-root user │   │ Checks     │  │
│  └───────────────┘    │ - Port 8080     │   └────────────┘  │
│                       │ - Memory: 512Mi │                   │
│                       │ - CPU: 1 vCPU   │                   │
│                       └─────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ VPC Connector   │
                    │ Internal Network│
                    │ 10.8.0.0/28     │
                    └─────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────┐
        │            IAM & Security               │
        │                                         │
        │ ┌─────────────────┐ ┌─────────────────┐ │
        │ │ Cloud Run SA    │ │ Invoker SA      │ │
        │ │ - Log Writer    │ │ - Run Invoker   │ │
        │ │ - Metric Writer │ │ (Internal Only) │ │
        │ └─────────────────┘ └─────────────────┘ │
        └─────────────────────────────────────────┘
```

### GCP Services Used

| Service | Purpose | Configuration |
|---------|---------|---------------|
| **Cloud Run** | Serverless container hosting | Auto-scaling 0-10 instances, 512Mi RAM, 1 vCPU |
| **Artifact Registry** | Docker image storage | Private repository `deploy-flaskapp` |
| **VPC Access Connector** | Internal networking | CIDR: 10.8.0.0/28, egress: private ranges only |
| **IAM** | Security & access control | Least-privilege service accounts |
| **Cloud Logging** | Application logs | Structured logging with severity levels |
| **Cloud Monitoring** | Service health metrics | CPU, memory, request metrics |

## 🧠 Design Decisions

### Why Cloud Run?

**Serverless Benefits:**
- **Zero Infrastructure Management**: No servers to patch or maintain
- **Automatic Scaling**: Scales from 0 to 10 instances based on traffic
- **Pay-per-Use**: Only charged for actual request processing time
- **Built-in Load Balancing**: Automatic traffic distribution

**Technical Advantages:**
- **Container Native**: Direct Docker deployment with no modification needed
- **HTTPS by Default**: Automatic SSL/TLS certificate management  
- **Health Checks**: Built-in startup, liveness, and readiness probes
- **Integrated Monitoring**: Native integration with Cloud Operations suite

**Cost Efficiency:**
- **Cold Start Optimization**: Fast container startup times
- **Request-based Pricing**: No charges during idle periods
- **Resource Optimization**: Configurable CPU and memory limits

### Security Architecture Strategy

**Defense in Depth Approach:**

1. **Network Security**:
   - VPC Access Connector for internal-only communication
   - Private egress traffic (`PRIVATE_RANGES_ONLY`)
   - No public internet exposure

2. **Identity and Access Management**:
   - Dedicated service accounts with minimal permissions
   - No use of default Compute Engine service account
   - Principle of least privilege enforcement

3. **Container Security**:
   - Non-root user execution (UID 1000)
   - Multi-stage Docker builds for production
   - Resource limits to prevent resource exhaustion
   - Health checks for application reliability

4. **Data Protection**:
   - HTTPS-only communication
   - No sensitive data stored in container images
   - Environment variables for configuration

### CI/CD Pipeline Design Philosophy

**Two-Stage Validation:**

1. **Quality Gate (All Branches)**:
   - Code linting with flake8
   - Unit test execution with pytest
   - Terraform formatting validation
   - Security scanning

2. **Deployment Gate (Main Branch Only)**:
   - Docker image building and scanning
   - Artifact Registry push with authentication
   - Infrastructure deployment with Terraform
   - Post-deployment health validation

**Infrastructure as Code Benefits:**
- **Reproducibility**: Consistent environments across deployments
- **Version Control**: Infrastructure changes tracked in Git
- **Rollback Capability**: Easy reversion to previous configurations
- **Documentation**: Infrastructure self-documented through code

## 🔒 Security Implementation

### Current Security Posture

| Security Control | Implementation | Status |
|------------------|----------------|--------|
| **Service Account Isolation** | Dedicated `text-analyzer-cloudrun-sa` | ✅ Implemented |
| **Least Privilege Access** | Only logging and monitoring permissions | ✅ Implemented |
| **Network Isolation** | VPC connector with private egress | ✅ Implemented |
| **No Public Access** | Service account-based authentication | ✅ Implemented |
| **Container Security** | Non-root user, resource limits | ✅ Implemented |
| **Secrets Management** | GitHub Secrets, no hardcoded credentials | ✅ Implemented |
| **HTTPS Enforcement** | Cloud Run automatic SSL/TLS | ✅ Implemented |

### Service Account Configuration

**Cloud Run Service Account** (`text-analyzer-cloudrun-sa`):
```hcl
# Minimal permissions for application runtime
roles/logging.logWriter      # Write application logs
roles/monitoring.metricWriter # Write custom metrics
```

**Invoker Service Account** (`text-analyzer-invoker-sa`):
```hcl
# Access control for service invocation
roles/run.invoker            # Invoke Cloud Run services
```

### Network Security Controls

```hcl
# VPC Access Configuration
vpc_access {
  connector = google_vpc_access_connector.connector.id
  egress    = "PRIVATE_RANGES_ONLY"  # No internet access
}

# VPC Connector Specification
resource "google_vpc_access_connector" "connector" {
  name          = "text-analyzer-connector"
  region        = "us-central1"
  ip_cidr_range = "10.8.0.0/28"      # Private IP range
  network       = "default"
}
```

## 🚀 Setup and Deployment Instructions

### Prerequisites Checklist

- [ ] Google Cloud SDK installed (`gcloud --version`)
- [ ] Docker installed (`docker --version`)
- [ ] Terraform >= 1.0 installed (`terraform --version`)
- [ ] Git installed (`git --version`)
- [ ] Active GCP project with billing enabled
- [ ] GitHub account for repository hosting

### Step 1: Initial GCP Authentication

```bash
# Authenticate with your Google account
gcloud auth login

# Set up application default credentials for Terraform
gcloud auth application-default login

# Set your project (replace with your actual project ID)
export PROJECT_ID="your-project-id"
gcloud config set project $PROJECT_ID

# Verify authentication and project
gcloud config list
gcloud projects describe $PROJECT_ID
```

### Step 2: Enable Required GCP APIs

```bash
# Enable all necessary APIs in one command
gcloud services enable \
  run.googleapis.com \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  iam.googleapis.com \
  vpcaccess.googleapis.com

# Verify APIs are enabled
gcloud services list --enabled --filter="name:run.googleapis.com OR name:artifactregistry.googleapis.com"
```

### Step 3: Create Artifact Registry Repository

```bash
# Create Docker repository for container images
gcloud artifacts repositories create deploy-flaskapp \
    --repository-format=docker \
    --location=us-central1 \
    --description="Docker repository for Flask text analyzer"

# Configure Docker authentication
gcloud auth configure-docker us-central1-docker.pkg.dev

# Verify repository creation
gcloud artifacts repositories list --location=us-central1
```

### Step 4: Clone and Configure Repository

```bash
# Clone your repository
git clone <your-repository-url>
cd deploy-flaskapp

# Verify project structure
ls -la
# Should show: app.py, Dockerfile, requirements.txt, terraform/, .github/
```

### Step 5: Configure Terraform Variables

**Create `terraform/terraform.tfvars` (DO NOT COMMIT THIS FILE):**

```bash
cd terraform

# Create configuration file with your specific values
cat > terraform.tfvars << EOF
project_id              = "your-actual-project-id"
region                  = "us-central1"
app_name               = "text-analyzer"
artifact_registry_repo = "deploy-flaskapp"
image_tag              = "latest"
EOF

# Verify .gitignore excludes this file
grep "terraform.tfvars" ../.gitignore
```

### Step 6: Deploy Infrastructure

```bash
# Initialize Terraform (downloads providers)
terraform init

# Validate configuration
terraform validate

# Preview changes
terraform plan

# Apply infrastructure (type 'yes' when prompted)
terraform apply

# Note the output values for testing
terraform output
```

### Step 7: Build and Deploy Application

```bash
# Return to project root
cd ..

# Build Docker image with proper tagging
docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp/text-analyzer:latest .

# Push image to Artifact Registry
docker push us-central1-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp/text-analyzer:latest

# Update Cloud Run service with new image
cd terraform
terraform apply  # This deploys the new image
```

### Step 8: Verify Deployment

```bash
# Get service URL from Terraform output
SERVICE_URL=$(terraform output -raw cloud_run_url)
echo "Service URL: $SERVICE_URL"

# Get invoker service account email
INVOKER_SA=$(terraform output -raw invoker_service_account_email)
echo "Invoker SA: $INVOKER_SA"
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow Architecture

The automated pipeline consists of two sequential jobs:

#### Job 1: Quality Assurance (`lint-and-test`)
- **Trigger**: All pushes and pull requests
- **Python Environment**: 3.11
- **Steps**:
  1. Code checkout
  2. Python dependency installation
  3. Flake8 linting (syntax and style checks)
  4. Pytest unit test execution
  5. Terraform formatting validation

#### Job 2: Build and Deploy (`build-and-deploy`)
- **Trigger**: Only pushes to `main` branch
- **Dependencies**: Requires `lint-and-test` to pass
- **Steps**:
  1. Google Cloud authentication
  2. Docker image building with commit SHA tagging
  3. Artifact Registry image push
  4. Terraform infrastructure deployment
  5. Service health validation
  6. Deployment URL output

### Required Repository Secrets

Configure these secrets in GitHub repository settings (`Settings > Secrets and variables > Actions`):

| Secret Name | Description | How to Obtain |
|-------------|-------------|---------------|
| `GCP_PROJECT_ID` | Your GCP project identifier | `gcloud config get-value project` |
| `GCP_SA_KEY` | Service account key JSON | Create dedicated CI/CD service account |

### Creating CI/CD Service Account

```bash
# Create dedicated service account for GitHub Actions
gcloud iam service-accounts create github-actions-sa \
    --display-name="GitHub Actions CI/CD Service Account" \
    --description="Automated deployment service account"

# Grant necessary permissions for CI/CD operations
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/run.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/artifactregistry.admin"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/iam.serviceAccountUser"

# Create and download service account key
gcloud iam service-accounts keys create github-actions-key.json \
    --iam-account=github-actions-sa@$PROJECT_ID.iam.gserviceaccount.com

# Display key content for GitHub secret (copy this output)
cat github-actions-key.json

# Clean up local key file for security
rm github-actions-key.json
```

### Pipeline Security Considerations

- **Secrets Isolation**: No secrets in repository code or logs
- **Least Privilege**: CI/CD service account has minimal required permissions
- **Branch Protection**: Deployment only from `main` branch
- **Validation Gates**: All quality checks must pass before deployment

## 🧪 Testing the Service

### Authentication Setup for Testing

Since the service is configured for internal access only, you need proper authentication:

```bash
# Method 1: Create invoker service account key
gcloud iam service-accounts keys create invoker-key.json \
    --iam-account=text-analyzer-invoker-sa@$PROJECT_ID.iam.gserviceaccount.com

# Activate the service account
gcloud auth activate-service-account --key-file=invoker-key.json

# Method 2: Grant your user account temporary access (for testing)
gcloud run services add-iam-policy-binding text-analyzer \
    --member="user:$(gcloud config get-value account)" \
    --role="roles/run.invoker" \
    --region=us-central1
```

### Health Check Testing

```bash
# Get authentication token
TOKEN=$(gcloud auth print-identity-token)

# Get service URL
SERVICE_URL=$(cd terraform && terraform output -raw cloud_run_url)

# Test health endpoint
curl -H "Authorization: Bearer $TOKEN" \
     "$SERVICE_URL/health"

# Expected response:
# {"status": "healthy"}
```

### Functional Testing

```bash
# Test text analysis endpoint
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"text": "Hello from secure Cloud Run deployment!"}' \
     "$SERVICE_URL/analyze"

# Expected response:
# {
#   "original_text": "Hello from secure Cloud Run deployment!",
#   "word_count": 6,
#   "character_count": 42
# }
```

### Error Handling Testing

```bash
# Test missing field error handling
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"invalid": "field"}' \
     "$SERVICE_URL/analyze"

# Expected response:
# {"error": "Missing required field: text"}

# Test invalid content type
curl -X POST \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: text/plain" \
     -d 'plain text' \
     "$SERVICE_URL/analyze"

# Expected response:
# {"error": "Content-Type must be application/json"}
```

## 📊 Monitoring and Troubleshooting

### Viewing Application Logs

```bash
# View recent logs
gcloud logging read \
    "resource.type=cloud_run_revision AND resource.labels.service_name=text-analyzer" \
    --project=$PROJECT_ID \
    --limit=20 \
    --format="table(timestamp,severity,textPayload)"

# Follow logs in real-time (requires beta components)
gcloud beta logging tail \
    "resource.type=cloud_run_revision AND resource.labels.service_name=text-analyzer" \
    --project=$PROJECT_ID
```

### Cloud Console Monitoring

- **Service Dashboard**: https://console.cloud.google.com/run/detail/us-central1/text-analyzer
- **Logs Viewer**: Service Dashboard → Logs tab
- **Metrics**: Service Dashboard → Metrics tab
- **Revisions**: Service Dashboard → Revisions tab

### Service Status Commands

```bash
# Detailed service information
gcloud run services describe text-analyzer \
    --region=us-central1 \
    --format="export"

# List all service revisions
gcloud run revisions list \
    --service=text-analyzer \
    --region=us-central1

# View service metrics
gcloud run services list \
    --filter="metadata.name=text-analyzer" \
    --format="table(metadata.name,status.url,status.conditions[0].status)"
```

### Common Troubleshooting Scenarios

#### Issue: 403 Forbidden Error
**Symptoms**: `403 Permission Denied` when accessing service
**Solution**:
```bash
# Check IAM policy bindings
gcloud run services get-iam-policy text-analyzer --region=us-central1

# Grant access if needed
gcloud run services add-iam-policy-binding text-analyzer \
    --member="serviceAccount:your-invoker-sa@project.iam.gserviceaccount.com" \
    --role="roles/run.invoker" \
    --region=us-central1
```

#### Issue: Container Image Not Found
**Symptoms**: `Image not found` or `pull access denied` errors
**Solution**:
```bash
# Verify image exists in Artifact Registry
gcloud artifacts docker images list us-central1-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp

# Check service account permissions
gcloud artifacts repositories get-iam-policy deploy-flaskapp --location=us-central1
```

#### Issue: VPC Connector Errors
**Symptoms**: `VPC connector not found` or network connectivity issues
**Solution**:
```bash
# Check VPC connector status
gcloud compute networks vpc-access connectors list --region=us-central1

# Verify connector configuration
gcloud compute networks vpc-access connectors describe text-analyzer-connector --region=us-central1
```

### Performance Monitoring

```bash
# View service metrics
gcloud monitoring metrics list --filter="resource.type=cloud_run_revision"

# Get request count metrics
gcloud monitoring time-series list \
    --filter='resource.type="cloud_run_revision" AND resource.label.service_name="text-analyzer"' \
    --interval-end-time=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
    --interval-start-time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
```

## 🔧 Maintenance and Updates

### Updating Application Code

1. **Make code changes** in your repository
2. **Commit and push** to `main` branch
3. **GitHub Actions automatically**:
   - Builds new Docker image
   - Pushes to Artifact Registry
   - Deploys to Cloud Run
   - Validates deployment

### Manual Deployment

```bash
# Build new image with timestamp tag
IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
docker build -t us-central1-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp/text-analyzer:$IMAGE_TAG .
docker push us-central1-docker.pkg.dev/$PROJECT_ID/deploy-flaskapp/text-analyzer:$IMAGE_TAG

# Update Terraform variables
echo "image_tag = \"$IMAGE_TAG\"" >> terraform/terraform.tfvars

# Deploy new version
cd terraform && terraform apply
```

### Infrastructure Updates

```bash
# Update Terraform configuration files
# Run terraform plan to review changes
cd terraform
terraform plan

# Apply infrastructure changes
terraform apply
```

## 📝 Environment Configuration

| Environment Variable | Purpose | Default Value |
|---------------------|---------|---------------|
| `PORT` | Container port (managed by Cloud Run) | 8080 |
| `ENVIRONMENT` | Runtime environment identifier | production |
| `PYTHONUNBUFFERED` | Python output buffering | 1 |
| `PYTHONDONTWRITEBYTECODE` | Python bytecode generation | 1 |

## 🤝 Contributing

### Development Workflow

1. **Fork the repository** and create a feature branch
2. **Make changes** following coding standards
3. **Run local tests**: `python -m pytest tests/`
4. **Lint code**: `flake8 . --max-line-length=127`
5. **Submit pull request** with clear description
6. **CI pipeline validates** changes automatically
7. **Merge after approval** triggers deployment

### Code Quality Standards

- **Python**: PEP 8 compliance with flake8
- **Terraform**: `terraform fmt` formatting
- **Docker**: Multi-stage builds for production
- **Testing**: Unit tests for all functions
- **Documentation**: Inline comments and README updates

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
