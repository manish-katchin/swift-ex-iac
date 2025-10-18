# SwiftX ECS Deployment

Complete ECS deployment solution for new AWS accounts with Parameter Store/Secrets Manager integration.

## 🎯 **What This Does**

**From scratch in new AWS account:**
1. Creates shared infrastructure (VPC, ECS Cluster)
2. Deploys services dynamically with secrets/config support
3. Fully automated, zero manual setup

## 🚀 **Quick Start**

### **Step 1: Deploy Infrastructure (ONCE)**
```bash
./deploy-infrastructure.sh -p swiftx-dev -e dev -r ap-south-1
```
Creates:
- VPC with public/private subnets, NAT Gateway
- ECS Cluster with proper IAM roles
- Ready for multiple services

### **Step 2: Deploy Security (WAF)**
```bash
# Deploy WAF protection for your load balancer
./deploy-security.sh -p swiftx-dev -e dev -l "arn:aws:elasticloadbalancing:ap-south-1:542005048192:loadbalancer/app/dev-swiftx-shared-alb/4b36588ad3b5f7d6" --waf-only
```
Creates:
- AWS WAF Web ACL with 5 security rules
- SQL injection protection
- Rate limiting (1000 req/5min per IP)
- IP reputation filtering
- Known bad inputs blocking

### **Step 3: Deploy Services**
```bash
# Deploy engines service on port 80 (default path /*)
./deploy-service.sh -p swiftx-dev -s engines -P 80

# Deploy API service on port 3000 with specific path routing
./deploy-service.sh -p swiftx-dev -s api -P 3000 --path '/api/*' --priority 200

# Deploy web service on port 8080 with specific path routing
./deploy-service.sh -p swiftx-dev -s web -P 8080 --path '/web/*' --priority 300
```

## 📁 **Files Explained**

### **CloudFormation Templates**
| File | Purpose | Creates |
|------|---------|---------|
| `bootstrap-network.yaml` | VPC infrastructure | VPC, Subnets, NAT Gateway, Internet Gateway |
| `engines-cluster.yaml` | ECS infrastructure | ECS Cluster, IAM Roles with secrets permissions |
| `engines-service-network.yaml` | Load balancer | ALB, Target Group, Security Group |
| `engines-ecs-service.yaml` | Application | ECS Service, Task Definition, Auto Scaling |
| `engines-ecr.yaml` | Container registry | ECR Repository |
| `waf-security.yaml` | Security protection | WAF Web ACL, Security Rules, ALB Association |

### **Scripts**
| File | Purpose | When to Use |
|------|---------|-------------|
| `deploy-infrastructure.sh` | Creates shared infrastructure | Run ONCE per environment |
| `deploy-security.sh` | Deploys WAF security protection | Run after infrastructure, before services |
| `deploy-service.sh` | Deploys individual services | Run for each service |

## 🔐 **Secrets & Configuration**

Your services automatically get:

### **Environment Variables:**
- `NODE_ENV` = environment (dev/prod)
- `PORT` = service port
- `AWS_REGION` = AWS region

### **Secrets from Parameter Store:**
- `DATABASE_URL` from `/dev/swiftx/engines/database_url`
- `API_KEY` from `/dev/swiftx/engines/api_key`

**Path Pattern:** `/{environment}/{component}/{service}/{secret_name}`

### **How to Add Secrets:**
```bash
# Add database URL
aws ssm put-parameter --name "/dev/swiftx/engines/database_url" --value "postgresql://user:pass@host:5432/db" --type "SecureString" --profile swiftx-dev

# Add API key
aws ssm put-parameter --name "/dev/swiftx/engines/api_key" --value "your-secret-api-key" --type "SecureString" --profile swiftx-dev
```

## 🏗️ **Infrastructure Created**

### **Shared (Created Once)**
- `dev-swiftx-bootstrap-network` - VPC, Subnets, NAT, **Shared ALB**
- `dev-swiftx-cluster` - ECS Cluster, IAM Roles
- `dev-swiftx-security-waf` - WAF Web ACL, Security Rules

### **Per Service**
- `dev-swiftx-{service}-iac-network` - Target Group, Security Group, **ALB Listener Rule**
- `dev-swiftx-{service}-ecr` - Container Registry
- `dev-swiftx-{service}-iac-ecs` - ECS Service

## 🐳 **Docker Image Deployment**

After running `deploy-service.sh`, you'll get ECR repository URL:

```bash
# Example output:
ECR Repository: 542005048192.dkr.ecr.ap-south-1.amazonaws.com/dev-swiftx-engines-ecr:latest

# Push your image:
docker tag your-app:latest 542005048192.dkr.ecr.ap-south-1.amazonaws.com/dev-swiftx-engines-ecr:latest
aws ecr get-login-password --region ap-south-1 --profile swiftx-dev | docker login --username AWS --password-stdin 542005048192.dkr.ecr.ap-south-1.amazonaws.com
docker push 542005048192.dkr.ecr.ap-south-1.amazonaws.com/dev-swiftx-engines-ecr:latest
```

## 🔄 **Adding New Services**

```bash
# Deploy worker service on port 5000 with unique priority
./deploy-service.sh -p swiftx-dev -s worker -P 5000 --path '/worker/*' --priority 400

# Add its secrets
aws ssm put-parameter --name "/dev/swiftx/worker/database_url" --value "..." --type "SecureString" --profile swiftx-dev
```

**Note:** Each service needs a unique priority (100, 200, 300, etc.) and optionally a path pattern for routing.

## 🌍 **Multi-Environment**

```bash
# Production environment
./deploy-infrastructure.sh -p swiftx-prod -e prod -r us-east-1
./deploy-service.sh -p swiftx-prod -s engines -P 80

# Staging environment  
./deploy-infrastructure.sh -p swiftx-staging -e staging -r eu-west-1
./deploy-service.sh -p swiftx-staging -s engines -P 80
```

## 🔧 **Troubleshooting**

### **Check Service Status**
```bash
aws ecs describe-services --cluster dev-swiftx-cluster --services dev-swiftx-engines-ecs-service --region ap-south-1 --profile swiftx-dev
```

### **Check ALB Health**
```bash
aws elbv2 describe-target-health --target-group-arn <from-aws-console> --region ap-south-1 --profile swiftx-dev
```

### **Common Issues**
- **Container won't start**: Check CloudWatch logs in `/aws/ecs/dev-swiftx-engines-common-log-group`
- **Health check fails**: Ensure your app responds on the configured port and health check path
- **Secrets not found**: Verify Parameter Store paths match exactly

## 🔒 **Security Features**

### **WAF Protection**
Your application is protected by AWS WAF with:
- **Core Rule Set**: Blocks common web exploits (XSS, CSRF, etc.)
- **Rate Limiting**: 1000 requests per 5 minutes per IP (2000 for production)
- **SQL Injection Protection**: Blocks SQL injection attacks
- **Known Bad Inputs**: Blocks malicious input patterns
- **IP Reputation Filter**: Blocks requests from known malicious IPs

### **Traffic Flow**
```
Internet → Domain → WAF (5 Rules) → ALB → ECS Service → Your App
```

### **Updating WAF Rules**

#### **Method 1: Update CloudFormation Template (Recommended)**
```bash
# Edit waf-security.yaml to modify rules, then redeploy
./deploy-security.sh -p swiftx-dev -e dev -l "arn:aws:elasticloadbalancing:ap-south-1:542005048192:loadbalancer/app/dev-swiftx-shared-alb/4b36588ad3b5f7d6" --waf-only
```

#### **Method 2: Add New Rules via AWS Console**
1. Go to AWS WAF Console → Web ACLs
2. Select `dev-swiftx-waf-acl`
3. Add new rules with higher priority numbers (6, 7, 8, etc.)
4. Rules are applied immediately

#### **Method 3: Update Existing Rules via AWS CLI**
```bash
# Example: Update rate limit from 1000 to 500
aws wafv2 update-web-acl \
  --scope REGIONAL \
  --id 42fdd2e9-44c9-4c4f-994a-17b1d081dc3f \
  --default-action Allow={} \
  --rules '[
    {
      "Name": "RateLimitRule",
      "Priority": 2,
      "Action": {"Block": {}},
      "Statement": {
        "RateBasedStatement": {
          "Limit": 500,
          "AggregateKeyType": "IP"
        }
      },
      "VisibilityConfig": {
        "SampledRequestsEnabled": true,
        "CloudWatchMetricsEnabled": true,
        "MetricName": "RateLimitMetric"
      }
    }
  ]' \
  --profile swiftx-dev \
  --region ap-south-1
```

#### **Common Rule Updates**
- **Rate Limiting**: Change limit (1000 → 500 for stricter, 1000 → 2000 for looser)
- **Geo-blocking**: Add/remove countries
- **Custom Rules**: Add specific patterns to block
- **Rule Priorities**: Reorder rules (lower number = higher priority)

## 🗑️ **Teardown Infrastructure**

When you need to completely remove all infrastructure:

### **Quick Teardown**
```bash
# Test what would be deleted (safe)
./teardown.sh -p swiftx-dev -e dev -r ap-south-1 --dry-run

# Normal teardown with confirmation
./teardown.sh -p swiftx-dev -e dev -r ap-south-1

# Force teardown without confirmation
./teardown.sh -p swiftx-dev -e dev -r ap-south-1 --force
```

### **What Gets Deleted**
The teardown script removes everything in the correct dependency order:

1. **ECS Services** - ECS services, ECR repositories, target groups
2. **Security** - WAF Web ACLs and rules
3. **ECS Cluster** - ECS cluster and IAM roles
4. **Network** - VPC, subnets, NAT Gateway, ALB
5. **Cleanup** - CloudWatch logs, Parameter Store, Secrets Manager

### **Safety Features**
- **Dry Run Mode**: Test what would be deleted without actually deleting
- **Dependency Handling**: Deletes resources in correct order
- **Error Recovery**: Retries failed deletions automatically
- **Verification**: Confirms each resource is completely deleted
- **Comprehensive**: Cleans up orphaned resources

### **Teardown Options**
| Option | Description |
|--------|-------------|
| `--dry-run` | Show what would be deleted without actually deleting |
| `--force` | Skip confirmation prompts |
| `-p <profile>` | AWS profile to use |
| `-e <environment>` | Environment name (dev, staging, prod) |
| `-r <region>` | AWS region |

## ✅ **Summary**

1. **Deploy infrastructure once**: `./deploy-infrastructure.sh`
2. **Deploy security (WAF)**: `./deploy-security.sh --waf-only`
3. **Add services**: `./deploy-service.sh -s <name> -P <port>`
4. **Add secrets**: Use Parameter Store with path pattern
5. **Deploy images**: Push to ECR repository
6. **Teardown when done**: `./teardown.sh -p <profile> -e <env> -r <region>`

**Result**: Secure, scalable ECS platform with WAF protection and proper secrets management! 🚀