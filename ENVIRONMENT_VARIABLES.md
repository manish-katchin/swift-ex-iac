# Environment Variables Management

## Overview
All environment variables are stored in AWS Parameter Store and fetched at runtime. No CloudFormation changes needed for new variables.

## Parameter Store Path Pattern
```
/${EnvironmentName}/${ComponentName}/${ServiceName}/<variable_name>
```

Example: `/dev/swiftx/engines/mongodb_conn_string`

## Adding New Environment Variables

### Method 1: AWS Console
1. Go to AWS Systems Manager → Parameter Store
2. Click "Create parameter"
3. Name: `/dev/swiftx/engines/NEW_VARIABLE_NAME`
4. Type: String or SecureString
5. Value: `your_value`
6. Click "Create parameter"

### Method 2: AWS CLI
```bash
aws ssm put-parameter \
  --name "/dev/swiftx/engines/NEW_VARIABLE_NAME" \
  --value "your_value" \
  --type "String" \
  --profile swiftx-dev \
  --region ap-south-1
```

## No Dockerfile Updates Needed!
The Dockerfile automatically fetches ALL parameters from Parameter Store dynamically. No code changes needed for new variables!

## Deploying Changes
**For new environment variables, you only need to restart the container:**

```bash
aws ecs update-service \
  --cluster dev-swiftx-engines-cluster \
  --service dev-swiftx-engines-ecs-service \
  --force-new-deployment \
  --profile swiftx-dev \
  --region ap-south-1
```

**No Docker image rebuild needed!** The container will automatically fetch the new parameters.

## Current Environment Variables
Based on your existing parameters, these are already configured:
- `mongodb_conn_string`
- `db_name`
- `password_salt_rounds`
- `jwt_secret`
- `gmail_client_id`
- `gmail_client_secret`
- `gmail_access_token`
- `gmail_refresh_token`
- `gmail_redirect_uri`
- All Alchemy Pay variables
- All Stellar variables
- All Moralis variables
- All Soroban variables
- All Ethereum variables
- And more...

## Benefits
- ✅ No CloudFormation changes needed
- ✅ Add variables anytime
- ✅ Just restart container to pick up changes
- ✅ All variables in one place (Parameter Store)
