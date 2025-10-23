#!/bin/bash

# Add Redis to existing infrastructure
# Usage: ./add-redis.sh [environment]

set -e

ENVIRONMENT=${1:-dev}
REGION="ap-south-1"
PROFILE="swiftx-dev"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Adding Redis to existing infrastructure...${NC}"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity --profile $PROFILE --region $REGION >/dev/null 2>&1; then
    echo -e "${RED}❌ AWS CLI not configured or SSO token expired${NC}"
    echo "Please run: aws sso login --profile $PROFILE"
    exit 1
fi

# Get VPC and subnet information from existing stack
echo -e "${YELLOW}🔍 Getting VPC and subnet information...${NC}"

VPC_ID=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT}-swiftx-bootstrap-network \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
    --output text)

PRIVATE_SUBNET_1=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT}-swiftx-bootstrap-network \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet1Id`].OutputValue' \
    --output text)

PRIVATE_SUBNET_2=$(aws cloudformation describe-stacks \
    --stack-name ${ENVIRONMENT}-swiftx-bootstrap-network \
    --profile $PROFILE \
    --region $REGION \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateSubnet2Id`].OutputValue' \
    --output text)

echo -e "${GREEN}✅ Found VPC: $VPC_ID${NC}"
echo -e "${GREEN}✅ Found Private Subnets: $PRIVATE_SUBNET_1, $PRIVATE_SUBNET_2${NC}"

# Create Redis subnet group
echo -e "${YELLOW}📦 Creating Redis subnet group...${NC}"
aws elasticache create-cache-subnet-group \
    --cache-subnet-group-name "${ENVIRONMENT}-swiftx-redis-subnet-group" \
    --cache-subnet-group-description "Subnet group for Redis cluster" \
    --subnet-ids $PRIVATE_SUBNET_1 $PRIVATE_SUBNET_2 \
    --profile $PROFILE \
    --region $REGION || echo "Subnet group may already exist"

# Create Redis security group
echo -e "${YELLOW}🔒 Creating Redis security group...${NC}"
SECURITY_GROUP_ID=$(aws ec2 create-security-group \
    --group-name "${ENVIRONMENT}-swiftx-redis-sg" \
    --description "Security group for Redis cluster" \
    --vpc-id $VPC_ID \
    --profile $PROFILE \
    --region $REGION \
    --query 'GroupId' \
    --output text 2>/dev/null || \
    aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${ENVIRONMENT}-swiftx-redis-sg" "Name=vpc-id,Values=$VPC_ID" \
    --profile $PROFILE \
    --region $REGION \
    --query 'SecurityGroups[0].GroupId' \
    --output text)

echo -e "${GREEN}✅ Security Group ID: $SECURITY_GROUP_ID${NC}"

# Add security group rule
aws ec2 authorize-security-group-ingress \
    --group-id $SECURITY_GROUP_ID \
    --protocol tcp \
    --port 6379 \
    --cidr 10.0.0.0/8 \
    --profile $PROFILE \
    --region $REGION 2>/dev/null || echo "Rule may already exist"

# Create Redis cluster
echo -e "${YELLOW}📦 Creating Redis cluster...${NC}"
aws elasticache create-replication-group \
    --replication-group-id "${ENVIRONMENT}-swiftx-redis" \
    --replication-group-description "Redis cluster for SwiftX proxy server" \
    --cache-node-type cache.t3.micro \
    --port 6379 \
    --engine redis \
    --engine-version 6.2 \
    --num-cache-clusters 1 \
    --cache-subnet-group-name "${ENVIRONMENT}-swiftx-redis-subnet-group" \
    --security-group-ids $SECURITY_GROUP_ID \
    --profile $PROFILE \
    --region $REGION || echo "Redis cluster may already exist"

echo -e "${GREEN}✅ Redis cluster created successfully!${NC}"

# Wait for cluster to be available
echo -e "${YELLOW}⏳ Waiting for Redis cluster to be available...${NC}"
aws elasticache wait replication-group-available \
    --replication-group-id "${ENVIRONMENT}-swiftx-redis" \
    --profile $PROFILE \
    --region $REGION

# Get Redis endpoint
echo -e "${YELLOW}📋 Getting Redis endpoint...${NC}"
REDIS_ENDPOINT=$(aws elasticache describe-replication-groups \
    --replication-group-id "${ENVIRONMENT}-swiftx-redis" \
    --profile $PROFILE \
    --region $REGION \
    --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' \
    --output text)

REDIS_PORT="6379"
REDIS_CONNECTION="redis://$REDIS_ENDPOINT:$REDIS_PORT"

echo -e "${GREEN}🎉 Redis Cache Details:${NC}"
echo -e "  Endpoint: ${GREEN}$REDIS_ENDPOINT${NC}"
echo -e "  Port: ${GREEN}$REDIS_PORT${NC}"
echo -e "  Connection String: ${GREEN}$REDIS_CONNECTION${NC}"

# Store Redis connection in Parameter Store
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

echo -e "${GREEN}✅ Redis setup complete!${NC}"
echo -e "${YELLOW}📝 Redis is running in private subnets and can be accessed by ECS services.${NC}"
