#!/bin/bash

# SwiftX Security Stack Deployment Script
# Deploys WAF and Hardened Security Groups

set -e

# Default values
PROFILE=""
ENVIRONMENT=""
COMPONENT="swiftx"
REGION="ap-south-1"
STACK_NAME=""
LOAD_BALANCER_ARN=""
VPC_ID=""
ALLOWED_CIDR="0.0.0.0/0"
PRIVATE_SUBNET_CIDR="10.0.0.0/16"
ENGINES_PORT="3000"
DEPLOY_WAF="true"
DEPLOY_SECURITY_GROUPS="true"
DRY_RUN="false"

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

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy SwiftX Security Stack (WAF + Hardened Security Groups)

OPTIONS:
    -p, --profile PROFILE           AWS profile to use (required)
    -e, --environment ENV           Environment name (dev/staging/prod) (required)
    -r, --region REGION             AWS region (default: ap-south-1)
    -s, --stack-name NAME           CloudFormation stack name (auto-generated if not provided)
    -l, --load-balancer-arn ARN     Load balancer ARN for WAF (required for WAF)
    -v, --vpc-id VPC_ID             VPC ID for security groups (required for security groups)
    -c, --component COMPONENT       Component name (default: swiftx)
    -P, --port PORT                 Engines service port (default: 3000)
    --allowed-cidr CIDR             Allowed CIDR blocks for ALB (default: 0.0.0.0/0)
    --private-subnet-cidr CIDR      Private subnet CIDR (default: 10.0.0.0/16)
    --waf-only                      Deploy only WAF (skip security groups)
    --security-groups-only          Deploy only security groups (skip WAF)
    --dry-run                       Show what would be deployed without actually deploying
    -h, --help                      Show this help message

EXAMPLES:
    # Deploy complete security stack
    $0 -p swiftx-dev -e dev -l "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/dev-swiftx-shared-alb/1234567890abcdef" -v "vpc-12345678"

    # Deploy only WAF
    $0 -p swiftx-dev -e dev --waf-only -l "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/dev-swiftx-shared-alb/1234567890abcdef"

    # Deploy with restricted CIDR
    $0 -p swiftx-dev -e dev -l "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/dev-swiftx-shared-alb/1234567890abcdef" -v "vpc-12345678" --allowed-cidr "203.0.113.0/24,198.51.100.0/24"

    # Dry run to see what would be deployed
    $0 -p swiftx-dev -e dev -l "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/dev-swiftx-shared-alb/1234567890abcdef" -v "vpc-12345678" --dry-run

REQUIREMENTS:
    - AWS CLI configured with appropriate permissions
    - CloudFormation templates: waf-security.yaml, security-groups-hardened.yaml
    - Load balancer ARN (for WAF deployment)
    - VPC ID (for security groups deployment)

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            REGION="$2"
            shift 2
            ;;
        -s|--stack-name)
            STACK_NAME="$2"
            shift 2
            ;;
        -l|--load-balancer-arn)
            LOAD_BALANCER_ARN="$2"
            shift 2
            ;;
        -v|--vpc-id)
            VPC_ID="$2"
            shift 2
            ;;
        -c|--component)
            COMPONENT="$2"
            shift 2
            ;;
        -P|--port)
            ENGINES_PORT="$2"
            shift 2
            ;;
        --allowed-cidr)
            ALLOWED_CIDR="$2"
            shift 2
            ;;
        --private-subnet-cidr)
            PRIVATE_SUBNET_CIDR="$2"
            shift 2
            ;;
        --waf-only)
            DEPLOY_SECURITY_GROUPS="false"
            shift
            ;;
        --security-groups-only)
            DEPLOY_WAF="false"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$PROFILE" ]]; then
    print_error "AWS profile is required. Use -p or --profile"
    exit 1
fi

if [[ -z "$ENVIRONMENT" ]]; then
    print_error "Environment is required. Use -e or --environment"
    exit 1
fi

# Set default stack name if not provided
if [[ -z "$STACK_NAME" ]]; then
    STACK_NAME="${ENVIRONMENT}-${COMPONENT}-security"
fi

# Validate WAF requirements
if [[ "$DEPLOY_WAF" == "true" && -z "$LOAD_BALANCER_ARN" ]]; then
    print_error "Load balancer ARN is required for WAF deployment. Use -l or --load-balancer-arn"
    exit 1
fi

# Validate Security Groups requirements
if [[ "$DEPLOY_SECURITY_GROUPS" == "true" && -z "$VPC_ID" ]]; then
    print_error "VPC ID is required for security groups deployment. Use -v or --vpc-id"
    exit 1
fi

# Check if templates exist
if [[ "$DEPLOY_WAF" == "true" && ! -f "waf-security.yaml" ]]; then
    print_error "WAF template 'waf-security.yaml' not found"
    exit 1
fi

if [[ "$DEPLOY_SECURITY_GROUPS" == "true" && ! -f "security-groups-hardened.yaml" ]]; then
    print_error "Security groups template 'security-groups-hardened.yaml' not found"
    exit 1
fi

# Function to deploy WAF
deploy_waf() {
    local waf_stack_name="${STACK_NAME}-waf"
    print_status "Deploying WAF stack: $waf_stack_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would deploy WAF with parameters:"
        echo "  Stack Name: $waf_stack_name"
        echo "  Environment: $ENVIRONMENT"
        echo "  Component: $COMPONENT"
        echo "  Load Balancer ARN: $LOAD_BALANCER_ARN"
        echo "  Region: $REGION"
        return 0
    fi
    
    aws cloudformation deploy \
        --template-file waf-security.yaml \
        --stack-name "$waf_stack_name" \
        --parameter-overrides \
            EnvironmentName="$ENVIRONMENT" \
            ComponentName="$COMPONENT" \
            LoadBalancerArn="$LOAD_BALANCER_ARN" \
        --capabilities CAPABILITY_IAM \
        --profile "$PROFILE" \
        --region "$REGION" \
        --tags \
            Environment="$ENVIRONMENT" \
            Component="$COMPONENT" \
            StackType="Security" \
            ManagedBy="CloudFormation"
    
    if [[ $? -eq 0 ]]; then
        print_success "WAF stack deployed successfully: $waf_stack_name"
        
        # Get WAF outputs
        local waf_arn=$(aws cloudformation describe-stacks \
            --stack-name "$waf_stack_name" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`WebACLArn`].OutputValue' \
            --output text)
        
        print_status "WAF Web ACL ARN: $waf_arn"
    else
        print_error "Failed to deploy WAF stack"
        exit 1
    fi
}

# Function to deploy Security Groups
deploy_security_groups() {
    local sg_stack_name="${STACK_NAME}-sg"
    print_status "Deploying Security Groups stack: $sg_stack_name"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_warning "DRY RUN: Would deploy Security Groups with parameters:"
        echo "  Stack Name: $sg_stack_name"
        echo "  Environment: $ENVIRONMENT"
        echo "  Component: $COMPONENT"
        echo "  VPC ID: $VPC_ID"
        echo "  Engines Port: $ENGINES_PORT"
        echo "  Allowed CIDR: $ALLOWED_CIDR"
        echo "  Private Subnet CIDR: $PRIVATE_SUBNET_CIDR"
        echo "  Region: $REGION"
        return 0
    fi
    
    aws cloudformation deploy \
        --template-file security-groups-hardened.yaml \
        --stack-name "$sg_stack_name" \
        --parameter-overrides \
            EnvironmentName="$ENVIRONMENT" \
            ComponentName="$COMPONENT" \
            PartName="engines" \
            VpcId="$VPC_ID" \
            EnginesServicePort="$ENGINES_PORT" \
            AllowedCIDRBlocks="$ALLOWED_CIDR" \
            PrivateSubnetCIDR="$PRIVATE_SUBNET_CIDR" \
        --profile "$PROFILE" \
        --region "$REGION" \
        --tags \
            Environment="$ENVIRONMENT" \
            Component="$COMPONENT" \
            StackType="Security" \
            ManagedBy="CloudFormation"
    
    if [[ $? -eq 0 ]]; then
        print_success "Security Groups stack deployed successfully: $sg_stack_name"
        
        # Get Security Group outputs
        local alb_sg_id=$(aws cloudformation describe-stacks \
            --stack-name "$sg_stack_name" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`ALBSecurityGroupId`].OutputValue' \
            --output text)
        
        local ecs_sg_id=$(aws cloudformation describe-stacks \
            --stack-name "$sg_stack_name" \
            --profile "$PROFILE" \
            --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`ECSSecurityGroupId`].OutputValue' \
            --output text)
        
        print_status "ALB Security Group ID: $alb_sg_id"
        print_status "ECS Security Group ID: $ecs_sg_id"
    else
        print_error "Failed to deploy Security Groups stack"
        exit 1
    fi
}

# Function to show security recommendations
show_security_recommendations() {
    print_status "Security Recommendations:"
    echo ""
    echo "1. 🔒 WAF Protection:"
    echo "   - SQL injection protection enabled"
    echo "   - XSS protection enabled"
    echo "   - Rate limiting configured"
    echo "   - Geo-blocking for suspicious countries"
    echo "   - IP reputation filtering"
    echo ""
    echo "2. 🛡️ Security Groups:"
    echo "   - ALB only accepts HTTP/HTTPS from internet"
    echo "   - ECS service only accepts traffic from ALB"
    echo "   - Database only accepts traffic from ECS"
    echo "   - Restricted outbound traffic"
    echo ""
    echo "3. 📊 Monitoring:"
    echo "   - WAF logs sent to CloudWatch"
    echo "   - Security group flow logs (recommended)"
    echo "   - CloudTrail for API monitoring (recommended)"
    echo ""
    echo "4. 🔄 Next Steps:"
    echo "   - Update existing ALB to use new security groups"
    echo "   - Update ECS service to use new security groups"
    echo "   - Enable VPC Flow Logs"
    echo "   - Set up CloudWatch alarms for WAF blocks"
    echo ""
}

# Main execution
main() {
    print_status "Starting SwiftX Security Stack Deployment"
    print_status "Environment: $ENVIRONMENT"
    print_status "Component: $COMPONENT"
    print_status "Region: $REGION"
    print_status "Stack Name: $STACK_NAME"
    echo ""
    
    # Deploy WAF if requested
    if [[ "$DEPLOY_WAF" == "true" ]]; then
        deploy_waf
        echo ""
    fi
    
    # Deploy Security Groups if requested
    if [[ "$DEPLOY_SECURITY_GROUPS" == "true" ]]; then
        deploy_security_groups
        echo ""
    fi
    
    if [[ "$DRY_RUN" == "false" ]]; then
        print_success "Security stack deployment completed successfully!"
        show_security_recommendations
    else
        print_warning "Dry run completed. No resources were actually deployed."
    fi
}

# Run main function
main

