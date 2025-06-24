#!/bin/bash

# Sports Handbook Q&A System Deployment Script

set -e

echo "🏈 Deploying Sports Handbook Q&A System..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="sports-handbook-qa"
ENVIRONMENT="dev"
AWS_REGION="us-east-1"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    command -v terraform >/dev/null 2>&1 || { print_error "Terraform is required but not installed."; exit 1; }
    command -v aws >/dev/null 2>&1 || { print_error "AWS CLI is required but not installed."; exit 1; }
    command -v python3 >/dev/null 2>&1 || { print_error "Python 3 is required but not installed."; exit 1; }
    command -v dotnet >/dev/null 2>&1 || { print_error ".NET 8 SDK is required but not installed."; exit 1; }
    command -v zip >/dev/null 2>&1 || { print_error "zip is required but not installed."; exit 1; }
    
    # Check AWS credentials
    aws sts get-caller-identity >/dev/null 2>&1 || { print_error "AWS credentials not configured."; exit 1; }
    
    print_status "✅ All prerequisites met"
}

# Build Python Lambda
build_python_lambda() {
    print_status "Building Python ingestion lambda..."
    
    cd lambda-ingestion
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Install dependencies
    pip install -r requirements.txt
    
    # Create deployment package
    rm -rf build/
    mkdir -p build/
    
    # Copy source files
    cp src/*.py build/
    
    # Copy dependencies
    cp -r venv/lib/python*/site-packages/* build/
    
    # Create zip file
    cd build
    zip -r ../pdf-ingestion-lambda.zip .
    cd ..
    
    # Move zip to terraform directory
    mv pdf-ingestion-lambda.zip ../infrastructure/
    
    deactivate
    cd ..
    
    print_status "✅ Python lambda built successfully"
}

# Build .NET Lambda
build_dotnet_lambda() {
    print_status "Building .NET Q&A lambda..."
    
    cd lambda-qa-dotnet/src
    
    # Restore dependencies
    dotnet restore
    
    # Build and publish
    dotnet publish -c Release -r linux-x64 --self-contained false
    
    # Create zip file
    cd bin/Release/net8.0/publish
    zip -r qa-lambda.zip .
    
    # Move zip to terraform directory
    mv qa-lambda.zip ../../../../../infrastructure/
    
    cd ../../../../..
    
    print_status "✅ .NET lambda built successfully"
}

# Deploy infrastructure
deploy_infrastructure() {
    print_status "Deploying infrastructure with Terraform..."
    
    cd infrastructure
    
    # Initialize Terraform
    terraform init
    
    # Plan deployment
    terraform plan \
        -var="aws_region=$AWS_REGION" \
        -var="project_name=$PROJECT_NAME" \
        -var="environment=$ENVIRONMENT"
    
    # Apply deployment
    terraform apply \
        -var="aws_region=$AWS_REGION" \
        -var="project_name=$PROJECT_NAME" \
        -var="environment=$ENVIRONMENT" \
        -auto-approve
    
    # Save outputs
    terraform output -json > outputs.json
    
    cd ..
    
    print_status "✅ Infrastructure deployed successfully"
}

# Display deployment information
show_deployment_info() {
    print_status "Deployment completed! 🎉"
    echo ""
    print_status "📋 Service Information:"
    
    if [ -f "infrastructure/outputs.json" ]; then
        S3_BUCKET=$(cat infrastructure/outputs.json | python3 -c "import sys, json; print(json.load(sys.stdin)['s3_bucket_name']['value'])")
        API_URL=$(cat infrastructure/outputs.json | python3 -c "import sys, json; print(json.load(sys.stdin)['api_gateway_url']['value'])")
        OPENSEARCH_ENDPOINT=$(cat infrastructure/outputs.json | python3 -c "import sys, json; print(json.load(sys.stdin)['opensearch_endpoint']['value'])")
        
        echo "📦 S3 Bucket: $S3_BUCKET"
        echo "🔗 API Endpoint: $API_URL"
        echo "🔍 OpenSearch: https://$OPENSEARCH_ENDPOINT"
    fi
    
    echo ""
    print_status "📖 Next Steps:"
    echo "1. Upload your PDF handbooks to the S3 bucket"
    echo "2. Test the API with a POST request to the API endpoint"
    echo "3. Set up SNS subscriptions for notifications"
    echo ""
    
    print_warning "Remember to configure your SNS topic subscriptions for notifications!"
}

# Test API endpoint
test_api() {
    if [ -f "infrastructure/outputs.json" ]; then
        API_URL=$(cat infrastructure/outputs.json | python3 -c "import sys, json; print(json.load(sys.stdin)['api_gateway_url']['value'])")
        
        print_status "Testing API endpoint..."
        
        curl -X POST "$API_URL" \
            -H "Content-Type: application/json" \
            -d '{
                "question": "What are the general rules for high school sports?",
                "maxResults": 3
            }' \
            --silent \
            --show-error \
            --fail \
            || print_warning "API test failed - this is expected if no documents are indexed yet"
    fi
}

# Cleanup function
cleanup() {
    print_status "Cleaning up temporary files..."
    rm -f infrastructure/pdf-ingestion-lambda.zip
    rm -f infrastructure/qa-lambda.zip
    rm -f infrastructure/outputs.json
}

# Main deployment flow
main() {
    echo "🏈 Sports Handbook Q&A System Deployment"
    echo "========================================"
    
    check_prerequisites
    build_python_lambda
    build_dotnet_lambda
    deploy_infrastructure
    show_deployment_info
    
    # Optional: Test the API
    read -p "Would you like to test the API endpoint? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_api
    fi
    
    # Optional: Cleanup
    read -p "Would you like to clean up temporary files? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cleanup
    fi
}

# Run main function
main "$@"