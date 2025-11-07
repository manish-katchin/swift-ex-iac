#!/bin/bash

# Deploy Service on Shared Infrastructure
# Usage: ./deploy-service.sh -p <profile> -s <service-name> -P <port>

set -e

# Source config file for default values (if not in CI environment)
if [ -z "$CI" ] && [ -f ./config ]; then
    . ./config
fi

# Default values (from config file or fallback)
PROFILE=""
SERVICE_NAME=""
SERVICE_PORT="3000"
PATH_PATTERN="/*"
PRIORITY="100"
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
COMPONENT_NAME="${COMPONENT_NAME:-swiftx}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
# Domain Support
DOMAIN_NAME=""
CERTIFICATE_ARN=""
ENABLE_HTTPS="${ENABLE_HTTPS:-false}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--profile)
      PROFILE="$2"
      shift 2
      ;;
    -e|--environment)
      ENVIRONMENT_NAME="$2"
      shift 2
      ;;
    -r|--region)
      AWS_REGION="$2"
      shift 2
      ;;
    -s|--service)
      SERVICE_NAME="$2"
      shift 2
      ;;
    -P|--port)
      SERVICE_PORT="$2"
      shift 2
      ;;
    --path)
      PATH_PATTERN="$2"
      shift 2
      ;;
    --priority)
      PRIORITY="$2"
      shift 2
      ;;
    --domain)
      DOMAIN_NAME="$2"
      shift 2
      ;;
    --certificate)
      CERTIFICATE_ARN="$2"
      shift 2
      ;;
    --https)
      ENABLE_HTTPS="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 -p <profile> -e <environment> -r <region> -s <service-name> -P <port> [--path <pattern>] [--priority <number>] [--domain <domain>] [--certificate <arn>] [--https]"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1 -s engines -P 3000"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1 -s api -P 3000 --path '/api/*' --priority 200"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1 -s engines -P 3000 --domain 'api.example.com' --certificate 'arn:aws:acm:...' --https"
      exit 0
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [[ -z "$PROFILE" ]]; then
  echo "Error: Profile is required. Use -p <profile>"
  exit 1
fi

if [[ -z "$SERVICE_NAME" ]]; then
  echo "Error: Service name is required. Use -s <service-name>"
  exit 1
fi

# Validate HTTPS parameters
if [[ "$ENABLE_HTTPS" == "true" ]]; then
  if [[ -z "$DOMAIN_NAME" ]]; then
    echo "Error: Domain name is required when enabling HTTPS. Use --domain <domain>"
    exit 1
  fi
  # Certificate ARN is optional - will be created automatically if not provided
fi

# Set AWS profile
PROFILE_OPT=""
if [[ -n "$PROFILE" ]]; then
  PROFILE_OPT="--profile $PROFILE"
  export AWS_PROFILE="$PROFILE"
fi

echo "=============================================="
echo "Deploying Service on Shared Infrastructure"
echo "=============================================="
echo "Profile: $PROFILE"
echo "Service: $SERVICE_NAME"
echo "Port: $SERVICE_PORT"
echo "Path Pattern: $PATH_PATTERN"
echo "Priority: $PRIORITY"
echo "Environment: $ENVIRONMENT_NAME"
echo "Component: $COMPONENT_NAME"
echo "Region: $AWS_REGION"
if [[ -n "$DOMAIN_NAME" ]]; then
  echo "Domain: $DOMAIN_NAME"
  echo "HTTPS: $ENABLE_HTTPS"
fi
echo "=============================================="

# Step 1: Get shared infrastructure outputs
echo "Step 1: Getting shared infrastructure outputs"
BOOTSTRAP_STACK_NAME="${ENVIRONMENT_NAME}-swiftx-bootstrap-network"
CLUSTER_STACK_NAME="${ENVIRONMENT_NAME}-swiftx-cluster"

VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
    --output text)

PRIVATE_SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnetIds`].OutputValue' \
    --output text)

PUBLIC_SUBNET_IDS=$(aws cloudformation describe-stacks \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`PublicSubnetIds`].OutputValue' \
    --output text)

SHARED_ALB_ARN=$(aws cloudformation describe-stacks \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`SharedALBArn`].OutputValue' \
    --output text)

SHARED_ALB_LISTENER_ARN=$(aws cloudformation describe-stacks \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`SharedALBListenerArn`].OutputValue' \
    --output text)

SHARED_ALB_HTTPS_LISTENER_ARN=$(aws cloudformation describe-stacks \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`SharedALBHTTPSListenerArn`].OutputValue' \
    --output text)

CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name $CLUSTER_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`ClusterName`].OutputValue' \
    --output text)

EXECUTION_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name $CLUSTER_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`ExecutionRoleArn`].OutputValue' \
    --output text)

TASK_ROLE_ARN=$(aws cloudformation describe-stacks \
    --stack-name $CLUSTER_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`TaskRoleArn`].OutputValue' \
    --output text)

echo "VPC ID: $VPC_ID"
echo "Private Subnet IDs: $PRIVATE_SUBNET_IDS"
echo "Shared ALB ARN: $SHARED_ALB_ARN"
echo "Shared ALB Listener ARN: $SHARED_ALB_LISTENER_ARN"
echo "Cluster Name: $CLUSTER_NAME"
echo "Execution Role ARN: $EXECUTION_ROLE_ARN"
echo "Task Role ARN: $TASK_ROLE_ARN"

# Step 2: Deploy Network Stack (ALB, Target Group, Security Group)
echo "Step 2: Deploying Network Stack"
NETWORK_STACK_NAME="${ENVIRONMENT_NAME}-${COMPONENT_NAME}-${SERVICE_NAME}-iac-network"

aws cloudformation deploy \
    --stack-name $NETWORK_STACK_NAME \
    --template-file engines-service-network.yaml \
    --region $AWS_REGION \
    --tags STAGE="$ENVIRONMENT_NAME" COMPONENT_NAME="$COMPONENT_NAME" PART_NAME="$SERVICE_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
    EnvironmentName=$ENVIRONMENT_NAME \
    ComponentName=$COMPONENT_NAME \
    PartName=$SERVICE_NAME \
    VpcId="$VPC_ID" \
    PrivateSubnetIds="$PRIVATE_SUBNET_IDS" \
    PublicSubnetIds="$PUBLIC_SUBNET_IDS" \
    EnginesServicePort=$SERVICE_PORT \
    LoadBalancerArn="$SHARED_ALB_ARN" \
    ListenerArn="$SHARED_ALB_LISTENER_ARN" \
    EnginesServiceHTTPSListenerArn="$SHARED_ALB_HTTPS_LISTENER_ARN" \
    PathPattern="$PATH_PATTERN" \
    Priority=$PRIORITY \
    DomainName="$DOMAIN_NAME" \
    CertificateArn="$CERTIFICATE_ARN" \
    EnableHTTPS="$ENABLE_HTTPS" \
    $PROFILE_OPT

# Step 3: Get network outputs
echo "Step 3: Getting network outputs"
SECURITY_GROUP_ID=$(aws cloudformation describe-stacks \
    --stack-name $NETWORK_STACK_NAME \
    --region $AWS_REGION \
    $PROFILE_OPT \
    --query 'Stacks[0].Outputs[?OutputKey==`EnginesServiceSecurityGroupId`].OutputValue' \
    --output text)

echo "Security Group ID: $SECURITY_GROUP_ID"

# Step 4: Deploy ECR Repository
echo "Step 4: Deploying ECR Repository"
ECR_STACK_NAME="${ENVIRONMENT_NAME}-${COMPONENT_NAME}-${SERVICE_NAME}-ecr"

aws cloudformation deploy \
    --stack-name $ECR_STACK_NAME \
    --template-file engines-ecr.yaml \
    --region $AWS_REGION \
    --tags STAGE="$ENVIRONMENT_NAME" COMPONENT_NAME="$COMPONENT_NAME" PART_NAME="$SERVICE_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
    EnvironmentName=$ENVIRONMENT_NAME \
    ComponentName=$COMPONENT_NAME \
    PartName=$SERVICE_NAME \
    $PROFILE_OPT

# Step 5: Deploy ECS Service
echo "Step 5: Deploying ECS Service"
ECS_STACK_NAME="${ENVIRONMENT_NAME}-${COMPONENT_NAME}-${SERVICE_NAME}-iac-ecs"

aws cloudformation deploy \
    --stack-name $ECS_STACK_NAME \
    --template-file engines-ecs-service.yaml \
    --region $AWS_REGION \
    --tags STAGE="$ENVIRONMENT_NAME" COMPONENT_NAME="$COMPONENT_NAME" PART_NAME="$SERVICE_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
    EnvironmentName=$ENVIRONMENT_NAME \
    ComponentName=$COMPONENT_NAME \
    PartName=$SERVICE_NAME \
    PrivateSubnetIds="$PRIVATE_SUBNET_IDS" \
    EnginesServicePort=$SERVICE_PORT \
    EnginesServiceSecurityGroupId="$SECURITY_GROUP_ID" \
    EnginesServiceExecutionRoleArn="$EXECUTION_ROLE_ARN" \
    EnginesServiceTaskRoleArn="$TASK_ROLE_ARN" \
    EnginesServiceCluster="$CLUSTER_NAME" \
    ForceNewDeployment="true" \
    $PROFILE_OPT

# Step 6: Environment variables are managed manually in Parameter Store
echo "Step 6: Environment variables managed in Parameter Store"
echo "To add new environment variables:"
echo "1. Add to Parameter Store: /${ENVIRONMENT_NAME}/${COMPONENT_NAME}/${SERVICE_NAME}/<variable_name>"
echo "2. Update Dockerfile startup script if needed"
echo "3. Redeploy Docker image"
echo "No CloudFormation changes needed!"

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --region $AWS_REGION $PROFILE_OPT --query 'Account' --output text)

echo "=============================================="
echo "Service deployment completed successfully!"
echo "=============================================="
echo ""
echo "ECR Repository: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT_NAME}-${COMPONENT_NAME}-${SERVICE_NAME}-ecr:latest"
echo ""
echo "To deploy your Docker image:"
echo "  docker tag your-image:tag ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT_NAME}-${COMPONENT_NAME}-${SERVICE_NAME}-ecr:latest"
echo "  aws ecr get-login-password --region ${AWS_REGION} ${PROFILE_OPT} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
echo "  docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ENVIRONMENT_NAME}-${COMPONENT_NAME}-${SERVICE_NAME}-ecr:latest"
