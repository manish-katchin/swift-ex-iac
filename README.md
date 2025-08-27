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

### **Step 2: Deploy Services**
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

### **Scripts**
| File | Purpose | When to Use |
|------|---------|-------------|
| `deploy-infrastructure.sh` | Creates shared infrastructure | Run ONCE per environment |
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

## ✅ **Summary**

1. **Deploy infrastructure once**: `./deploy-infrastructure.sh`
2. **Add services**: `./deploy-service.sh -s <name> -P <port>`
3. **Add secrets**: Use Parameter Store with path pattern
4. **Deploy images**: Push to ECR repository

**Result**: Scalable ECS platform with proper secrets management! 🚀