#!/bin/bash

# Deploy Redis cache for SwiftX proxy server
# Usage: ./deploy-redis.sh [environment] [bootstrap-stack-name]

set -e

# Source config file for default values (if not in CI environment)
if [ -z "$CI" ] && [ -f ./config ]; then
    . ./config
fi

# Configuration (from config file or fallback)
ENVIRONMENT=${1:-${ENVIRONMENT_NAME:-dev}}
BOOTSTRAP_STACK_NAME=${2:-"${ENVIRONMENT}-swiftx-bootstrap-network"}
STACK_NAME="${ENVIRONMENT}-swiftx-redis"
REGION="${AWS_REGION:-ap-south-1}"
PROFILE="swiftx-dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying Redis cache for SwiftX proxy server...${NC}"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity --profile $PROFILE --region $REGION >/dev/null 2>&1; then
    echo -e "${RED}❌ AWS CLI not configured or SSO token expired${NC}"
    echo "Please run: aws sso login --profile $PROFILE"
    exit 1
fi

# Check if bootstrap stack exists
echo -e "${YELLOW}🔍 Checking bootstrap network stack...${NC}"

if ! aws cloudformation describe-stacks --stack-name $BOOTSTRAP_STACK_NAME --profile $PROFILE --region $REGION >/dev/null 2>&1; then
    echo -e "${RED}❌ Bootstrap stack '$BOOTSTRAP_STACK_NAME' not found${NC}"
    echo "Please deploy the bootstrap network first:"
    echo "  ./deploy-infrastructure.sh"
    exit 1
fi

echo -e "${GREEN}✅ Bootstrap stack found: $BOOTSTRAP_STACK_NAME${NC}"

# Deploy the CloudFormation stack
echo -e "${YELLOW}📦 Deploying CloudFormation stack: $STACK_NAME${NC}"

aws cloudformation deploy \
    --template-file redis-cache.yaml \
    --stack-name $STACK_NAME \
    --parameter-overrides \
        Environment=$ENVIRONMENT \
        BootstrapStackName=$BOOTSTRAP_STACK_NAME \
    --capabilities CAPABILITY_IAM \
    --profile $PROFILE \
    --region $REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Redis cache deployed successfully!${NC}"
    
    # Get Redis endpoint from ElastiCache
    echo -e "${YELLOW}📋 Getting Redis endpoint from ElastiCache...${NC}"
    
    # Get the Redis cluster ID from stack outputs
    REDIS_CLUSTER_ID=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --profile $PROFILE \
        --region $REGION \
        --query 'Stacks[0].Outputs[?OutputKey==`RedisClusterId`].OutputValue' \
        --output text)
    
    # Get Redis endpoint from ElastiCache
    REDIS_ENDPOINT=$(aws elasticache describe-replication-groups \
        --replication-group-id $REDIS_CLUSTER_ID \
        --profile $PROFILE \
        --region $REGION \
        --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' \
        --output text)
    
    REDIS_PORT="6379"
    REDIS_CONNECTION="redis://$REDIS_ENDPOINT:$REDIS_PORT"
    
    echo -e "${GREEN}🎉 Redis Cache Details:${NC}"
    echo -e "  Cluster ID: ${GREEN}$REDIS_CLUSTER_ID${NC}"
    echo -e "  Endpoint: ${GREEN}$REDIS_ENDPOINT${NC}"
    echo -e "  Port: ${GREEN}$REDIS_PORT${NC}"
    echo -e "  Connection String: ${GREEN}$REDIS_CONNECTION${NC}"
    
    # Store Redis connection string in Parameter Store
    echo -e "${YELLOW}💾 Storing Redis connection in Parameter Store...${NC}"
    
    aws ssm put-parameter \
        --name "/swiftx/$ENVIRONMENT/proxy/REDIS_HOST" \
        --value "$REDIS_ENDPOINT" \
        --type "String" \
        --overwrite \
        --profile $PROFILE \
        --region $REGION
    
    aws ssm put-parameter \
        --name "/swiftx/$ENVIRONMENT/proxy/REDIS_PORT" \
        --value "$REDIS_PORT" \
        --type "String" \
        --overwrite \
        --profile $PROFILE \
        --region $REGION
    
    aws ssm put-parameter \
        --name "/swiftx/$ENVIRONMENT/proxy/REDIS_URL" \
        --value "$REDIS_CONNECTION" \
        --type "String" \
        --overwrite \
        --profile $PROFILE \
        --region $REGION
    
    echo -e "${GREEN}✅ Redis connection details stored in Parameter Store${NC}"
    echo -e "${YELLOW}📝 Next steps:${NC}"
    echo -e "  1. Update your proxy server environment variables"
    echo -e "  2. Deploy the proxy server to ECS"
    echo -e "  3. Test the Redis connection"
    
else
    echo -e "${RED}❌ Failed to deploy Redis cache${NC}"
    exit 1
fi
