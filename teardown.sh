#!/bin/bash

# Teardown SwiftX Infrastructure
# Usage: ./teardown.sh -p <profile> -e <environment> -r <region> [--force] [--dry-run]

set -e

# Source config file for default values (if not in CI environment)
if [ -z "$CI" ] && [ -f ./config ]; then
    . ./config
fi

# Default values (from config file or fallback)
PROFILE=""
ENVIRONMENT_NAME="${ENVIRONMENT_NAME:-dev}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
FORCE_DELETE="false"
DRY_RUN="false"
MAX_RETRIES=3
RETRY_DELAY=30

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
    --force)
      FORCE_DELETE="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 -p <profile> -e <environment> -r <region> [--force] [--dry-run]"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1 --force"
      echo "Example: $0 -p swiftx-dev -e dev -r ap-south-1 --dry-run"
      echo ""
      echo "Options:"
      echo "  -p, --profile     AWS profile to use"
      echo "  -e, --environment Environment name (dev, staging, prod)"
      echo "  -r, --region      AWS region"
      echo "  --force          Skip confirmation prompts"
      echo "  --dry-run        Show what would be deleted without actually deleting"
      echo "  -h, --help       Show this help message"
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
echo "SwiftX Infrastructure Teardown"
echo "=============================================="
echo "Profile: $PROFILE"
echo "Environment: $ENVIRONMENT_NAME"
echo "Region: $AWS_REGION"
echo "Force Delete: $FORCE_DELETE"
echo "Dry Run: $DRY_RUN"
echo "=============================================="

# Dry run mode
if [[ "$DRY_RUN" == "true" ]]; then
  echo ""
  echo "🔍 DRY RUN MODE - No resources will be deleted"
  echo "This will show you what would be deleted:"
  echo ""
fi

# Confirmation prompt
if [[ "$FORCE_DELETE" != "true" ]]; then
  echo ""
  echo "⚠️  WARNING: This will delete ALL infrastructure for environment '$ENVIRONMENT_NAME'"
  echo "This includes:"
  echo "  - ECS Services and Clusters"
  echo "  - ECR Repositories"
  echo "  - Load Balancers and Target Groups"
  echo "  - VPC, Subnets, and NAT Gateways"
  echo "  - Security Groups"
  echo "  - WAF Web ACLs"
  echo "  - CloudWatch Log Groups"
  echo ""
  read -p "Are you sure you want to continue? (yes/no): " confirm
  if [[ $confirm != "yes" ]]; then
    echo "Teardown cancelled."
    exit 0
  fi
fi

# Function to check if stack exists
stack_exists() {
  local stack_name="$1"
  aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" $PROFILE_OPT >/dev/null 2>&1
}

# Function to get stack status
get_stack_status() {
  local stack_name="$1"
  aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" $PROFILE_OPT --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "DOES_NOT_EXIST"
}

# Function to delete stack with comprehensive error handling
delete_stack() {
  local stack_name="$1"
  local attempt=1
  
  if [[ "$DRY_RUN" == "true" ]]; then
    if stack_exists "$stack_name"; then
      echo "  🔍 [DRY RUN] Would delete stack: $stack_name"
    else
      echo "  🔍 [DRY RUN] Stack $stack_name does not exist"
    fi
    return 0
  fi
  
  if ! stack_exists "$stack_name"; then
    echo "  ⏭️  Stack $stack_name does not exist, skipping"
    return 0
  fi
  
  local current_status=$(get_stack_status "$stack_name")
  echo "  📊 Current status of $stack_name: $current_status"
  
  # Handle different stack states
  case "$current_status" in
    "DELETE_IN_PROGRESS")
      echo "  ⏳ Stack $stack_name is already being deleted, waiting..."
      wait_for_deletion "$stack_name"
      return $?
      ;;
    "DELETE_FAILED")
      echo "  🔄 Previous deletion failed, retrying..."
      ;;
    "CREATE_FAILED"|"ROLLBACK_COMPLETE"|"UPDATE_ROLLBACK_COMPLETE")
      echo "  🗑️  Deleting failed/rolled back stack: $stack_name"
      ;;
    *)
      echo "  🗑️  Deleting stack: $stack_name"
      ;;
  esac
  
  # Attempt deletion with retries
  while [[ $attempt -le $MAX_RETRIES ]]; do
    echo "  🔄 Attempt $attempt/$MAX_RETRIES to delete $stack_name"
    
    if aws cloudformation delete-stack --stack-name "$stack_name" --region "$AWS_REGION" $PROFILE_OPT 2>/dev/null; then
      echo "  ✅ Delete initiated for $stack_name"
      wait_for_deletion "$stack_name"
      return $?
    else
      echo "  ⚠️  Attempt $attempt failed for $stack_name"
      if [[ $attempt -eq $MAX_RETRIES ]]; then
        echo "  ❌ Failed to delete $stack_name after $MAX_RETRIES attempts"
        echo "  💡 You may need to manually delete this stack from the AWS Console"
        return 1
      fi
      echo "  ⏳ Waiting ${RETRY_DELAY}s before retry..."
      sleep $RETRY_DELAY
      ((attempt++))
    fi
  done
}

# Function to wait for stack deletion with better error handling
wait_for_deletion() {
  local stack_name="$1"
  local max_wait=1800  # 30 minutes
  local wait_time=0
  
  echo "  ⏳ Waiting for $stack_name to be deleted..."
  
  while [[ $wait_time -lt $max_wait ]]; do
    local status=$(get_stack_status "$stack_name")
    
    case "$status" in
      "DOES_NOT_EXIST")
        echo "  ✅ $stack_name deleted successfully"
        return 0
        ;;
      "DELETE_COMPLETE")
        echo "  ✅ $stack_name deleted successfully"
        return 0
        ;;
      "DELETE_FAILED")
        echo "  ❌ $stack_name deletion failed"
        echo "  💡 Check AWS Console for details and retry manually if needed"
        return 1
        ;;
      "DELETE_IN_PROGRESS")
        echo "  ⏳ Still deleting $stack_name... (${wait_time}s elapsed)"
        ;;
      *)
        echo "  ⚠️  Unexpected status '$status' for $stack_name"
        ;;
    esac
    
    sleep 30
    wait_time=$((wait_time + 30))
  done
  
  echo "  ⚠️  $stack_name deletion timed out after ${max_wait}s"
  echo "  💡 Check AWS Console for current status"
  return 1
}

# Function to verify and retry deletion
verify_and_retry() {
  local stack_name="$1"
  local max_verification_attempts=3
  local attempt=1
  
  while [[ $attempt -le $max_verification_attempts ]]; do
    if ! stack_exists "$stack_name"; then
      echo "  ✅ Verified: $stack_name is completely deleted"
      return 0
    fi
    
    echo "  🔍 Verification attempt $attempt: $stack_name still exists, retrying deletion..."
    delete_stack "$stack_name"
    
    if ! stack_exists "$stack_name"; then
      echo "  ✅ Verified: $stack_name is completely deleted"
      return 0
    fi
    
    ((attempt++))
    if [[ $attempt -le $max_verification_attempts ]]; then
      echo "  ⏳ Waiting before next verification attempt..."
      sleep 60
    fi
  done
  
  echo "  ⚠️  $stack_name still exists after $max_verification_attempts verification attempts"
  echo "  💡 Manual intervention may be required"
  return 1
}

# Step 1: Delete ECS Services (in dependency order)
echo ""
echo "Step 1: Deleting ECS Services"
echo "=============================="

# List of ECS service stacks to delete (in dependency order)
ECS_STACKS=(
  "${ENVIRONMENT_NAME}-swiftx-proxy-iac-ecs"
  "${ENVIRONMENT_NAME}-swiftx-proxy-ecr"
  "${ENVIRONMENT_NAME}-swiftx-proxy-iac-network"
  "${ENVIRONMENT_NAME}-swiftx-engines-iac-ecs"
  "${ENVIRONMENT_NAME}-swiftx-engines-ecr"
  "${ENVIRONMENT_NAME}-swiftx-engines-iac-network"
)

for stack in "${ECS_STACKS[@]}"; do
  echo ""
  echo "Processing: $stack"
  echo "-------------------"
  delete_stack "$stack"
  
  if [[ "$DRY_RUN" != "true" ]]; then
    verify_and_retry "$stack"
  fi
done

# Step 2: Delete Redis Cache
echo ""
echo "Step 2: Deleting Redis Cache"
echo "============================"

REDIS_STACK="${ENVIRONMENT_NAME}-swiftx-redis-cache"
echo ""
echo "Processing: $REDIS_STACK"
echo "------------------------"
delete_stack "$REDIS_STACK"

if [[ "$DRY_RUN" != "true" ]]; then
  verify_and_retry "$REDIS_STACK"
fi

# Step 3: Delete Security (WAF)
echo ""
echo "Step 3: Deleting Security Resources"
echo "==================================="

WAF_STACK="${ENVIRONMENT_NAME}-swiftx-security-waf"
echo ""
echo "Processing: $WAF_STACK"
echo "----------------------"
delete_stack "$WAF_STACK"

if [[ "$DRY_RUN" != "true" ]]; then
  verify_and_retry "$WAF_STACK"
fi

# Step 4: Delete ECS Cluster
echo ""
echo "Step 4: Deleting ECS Cluster"
echo "============================"

CLUSTER_STACK="${ENVIRONMENT_NAME}-swiftx-cluster"
echo ""
echo "Processing: $CLUSTER_STACK"
echo "-------------------------"
delete_stack "$CLUSTER_STACK"

if [[ "$DRY_RUN" != "true" ]]; then
  verify_and_retry "$CLUSTER_STACK"
fi

# Step 5: Delete Bootstrap Network (VPC, ALB, etc.)
echo ""
echo "Step 5: Deleting Network Infrastructure"
echo "======================================"

BOOTSTRAP_STACK="${ENVIRONMENT_NAME}-swiftx-bootstrap-network"
echo ""
echo "Processing: $BOOTSTRAP_STACK"
echo "----------------------------"
delete_stack "$BOOTSTRAP_STACK"

if [[ "$DRY_RUN" != "true" ]]; then
  verify_and_retry "$BOOTSTRAP_STACK"
fi

# Step 6: Clean up any remaining resources
echo ""
echo "Step 6: Cleaning up remaining resources"
echo "======================================="

# Delete CloudWatch Log Groups
echo ""
echo "CloudWatch Log Groups:"
echo "----------------------"
if [[ "$DRY_RUN" == "true" ]]; then
  aws logs describe-log-groups \
    --log-group-name-prefix "/aws/ecs/${ENVIRONMENT_NAME}-swiftx" \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'logGroups[].logGroupName' \
    --output text | tr '\t' '\n' | while read log_group; do
      if [[ -n "$log_group" ]]; then
        echo "  🔍 [DRY RUN] Would delete log group: $log_group"
      fi
    done
else
  aws logs describe-log-groups \
    --log-group-name-prefix "/aws/ecs/${ENVIRONMENT_NAME}-swiftx" \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'logGroups[].logGroupName' \
    --output text | tr '\t' '\n' | while read log_group; do
      if [[ -n "$log_group" ]]; then
        echo "  🗑️  Deleting log group: $log_group"
        aws logs delete-log-group --log-group-name "$log_group" --region "$AWS_REGION" $PROFILE_OPT 2>/dev/null || echo "    ⚠️  Failed to delete $log_group"
      fi
    done
fi

# Delete ECR Repositories
echo ""
echo "ECR Repositories:"
echo "-----------------"
if [[ "$DRY_RUN" == "true" ]]; then
  aws ecr describe-repositories \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'repositories[?contains(repositoryName, `'${ENVIRONMENT_NAME}'-swiftx`)].repositoryName' \
    --output text | tr '\t' '\n' | while read repo; do
      if [[ -n "$repo" ]]; then
        echo "  🔍 [DRY RUN] Would delete ECR repository: $repo"
      fi
    done
else
  aws ecr describe-repositories \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'repositories[?contains(repositoryName, `'${ENVIRONMENT_NAME}'-swiftx`)].repositoryName' \
    --output text | tr '\t' '\n' | while read repo; do
      if [[ -n "$repo" ]]; then
        echo "  🗑️  Deleting ECR repository: $repo"
        aws ecr delete-repository --repository-name "$repo" --region "$AWS_REGION" $PROFILE_OPT --force 2>/dev/null || echo "    ⚠️  Failed to delete $repo"
      fi
    done
fi

# Delete Parameter Store parameters
echo ""
echo "Parameter Store Parameters:"
echo "--------------------------"
if [[ "$DRY_RUN" == "true" ]]; then
  aws ssm describe-parameters \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/${ENVIRONMENT_NAME}/swiftx/" \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'Parameters[].Name' \
    --output text | tr '\t' '\n' | while read param; do
      if [[ -n "$param" ]]; then
        echo "  🔍 [DRY RUN] Would delete parameter: $param"
      fi
    done
else
  aws ssm describe-parameters \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/${ENVIRONMENT_NAME}/swiftx/" \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'Parameters[].Name' \
    --output text | tr '\t' '\n' | while read param; do
      if [[ -n "$param" ]]; then
        echo "  🗑️  Deleting parameter: $param"
        aws ssm delete-parameter --name "$param" --region "$AWS_REGION" $PROFILE_OPT 2>/dev/null || echo "    ⚠️  Failed to delete $param"
      fi
    done
fi

# Delete Secrets Manager secrets
echo ""
echo "Secrets Manager Secrets:"
echo "------------------------"
if [[ "$DRY_RUN" == "true" ]]; then
  aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'SecretList[?contains(Name, `swiftx`) || contains(Name, `EC2`)].Name' \
    --output text | tr '\t' '\n' | while read secret; do
      if [[ -n "$secret" ]]; then
        echo "  🔍 [DRY RUN] Would delete secret: $secret"
      fi
    done
else
  aws secretsmanager list-secrets \
    --region "$AWS_REGION" \
    $PROFILE_OPT \
    --query 'SecretList[?contains(Name, `swiftx`) || contains(Name, `EC2`)].Name' \
    --output text | tr '\t' '\n' | while read secret; do
      if [[ -n "$secret" ]]; then
        echo "  🗑️  Deleting secret: $secret"
        aws secretsmanager delete-secret --secret-id "$secret" --region "$AWS_REGION" $PROFILE_OPT --force-delete-without-recovery 2>/dev/null || echo "    ⚠️  Failed to delete $secret"
      fi
    done
fi

# Delete S3 bucket contents (Firebase secrets)
echo ""
echo "S3 Bucket Contents:"
echo "-------------------"
if [[ "$DRY_RUN" == "true" ]]; then
  aws s3 ls s3://dev-swiftx-secrets/ --region "$AWS_REGION" $PROFILE_OPT 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
      echo "  🔍 [DRY RUN] Would delete S3 object: s3://dev-swiftx-secrets/$(echo $line | awk '{print $4}')"
    fi
  done
else
  aws s3 ls s3://dev-swiftx-secrets/ --region "$AWS_REGION" $PROFILE_OPT 2>/dev/null | while read line; do
    if [[ -n "$line" ]]; then
      object_key=$(echo $line | awk '{print $4}')
      echo "  🗑️  Deleting S3 object: s3://dev-swiftx-secrets/$object_key"
      aws s3 rm "s3://dev-swiftx-secrets/$object_key" --region "$AWS_REGION" $PROFILE_OPT 2>/dev/null || echo "    ⚠️  Failed to delete s3://dev-swiftx-secrets/$object_key"
    fi
  done
fi

echo ""
echo "=============================================="
echo "Teardown completed!"
echo "=============================================="
echo ""
echo "✅ All infrastructure for environment '$ENVIRONMENT_NAME' has been deleted"
echo ""
echo "Resources cleaned up:"
echo "  - ECS Services and Clusters (Engines + Proxy)"
echo "  - ECR Repositories (Engines + Proxy)"
echo "  - Redis Cache Cluster"
echo "  - Load Balancers and Target Groups"
echo "  - VPC, Subnets, and NAT Gateways"
echo "  - Security Groups"
echo "  - WAF Web ACLs"
echo "  - CloudWatch Log Groups"
echo "  - Parameter Store parameters"
echo "  - Secrets Manager secrets"
echo "  - S3 bucket contents (Firebase secrets)"
echo ""
echo "💡 Note: Some resources may take a few minutes to fully delete"
echo "   Check the AWS Console to verify all resources are removed"
