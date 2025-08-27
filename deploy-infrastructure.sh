#!/bin/bash

# Deploy Shared Infrastructure (run once)
# Usage: ./deploy-infrastructure.sh -p <profile> -e <environment> -r <region>

set -e

# Default values
PROFILE=""
ENVIRONMENT_NAME="dev"
COMPONENT_NAME="swiftx"
AWS_REGION="ap-south-1"

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
    -h|--help)
      echo "Usage: $0 -p <profile> [-e <environment>] [-r <region>]"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1"
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

# Set AWS profile
PROFILE_OPT=""
if [[ -n "$PROFILE" ]]; then
  PROFILE_OPT="--profile $PROFILE"
  export AWS_PROFILE="$PROFILE"
fi

echo "=============================================="
echo "Deploying Shared Infrastructure"
echo "=============================================="
echo "Profile: $PROFILE"
echo "Environment: $ENVIRONMENT_NAME"
echo "Component: $COMPONENT_NAME"
echo "Region: $AWS_REGION"
echo "=============================================="

# Step 1: Deploy Bootstrap Network
echo "Step 1: Deploying Bootstrap Network"
BOOTSTRAP_STACK_NAME="${ENVIRONMENT_NAME}-${COMPONENT_NAME}-bootstrap-network"

# Get availability zones
AVAILABILITY_ZONES=$(aws ec2 describe-availability-zones \
    --region $AWS_REGION \
    --query 'AvailabilityZones[0:2].ZoneName' \
    --output text | tr '\t' ',')

aws cloudformation deploy \
    --stack-name $BOOTSTRAP_STACK_NAME \
    --template-file bootstrap-network.yaml \
    --region $AWS_REGION \
    --tags STAGE="$ENVIRONMENT_NAME" COMPONENT_NAME="$COMPONENT_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
    EnvironmentName=$ENVIRONMENT_NAME \
    ComponentName=$COMPONENT_NAME \
    PartName="shared" \
    AvailabilityZones="$AVAILABILITY_ZONES" \
    $PROFILE_OPT

echo "Bootstrap network deployed successfully!"

# Step 2: Deploy Shared ECS Cluster
echo "Step 2: Deploying Shared ECS Cluster"
CLUSTER_STACK_NAME="${ENVIRONMENT_NAME}-${COMPONENT_NAME}-cluster"

aws cloudformation deploy \
    --stack-name $CLUSTER_STACK_NAME \
    --template-file engines-cluster.yaml \
    --region $AWS_REGION \
    --tags STAGE="$ENVIRONMENT_NAME" COMPONENT_NAME="$COMPONENT_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides \
    EnvironmentName=$ENVIRONMENT_NAME \
    ComponentName=$COMPONENT_NAME \
    $PROFILE_OPT

echo "Shared ECS cluster deployed successfully!"
echo "=============================================="
echo "Shared infrastructure deployed!"
echo "=============================================="
echo ""
echo "Now you can deploy services using:"
echo "  ./deploy-service.sh -p $PROFILE -s <service-name> -P <port>"
