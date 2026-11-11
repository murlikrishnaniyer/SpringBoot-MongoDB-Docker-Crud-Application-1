# GitHub Actions CI/CD Setup Guide

## Overview

Your project now has a complete GitHub Actions workflow that:
- ✅ Builds and tests on every push
- ✅ Scans for security vulnerabilities
- ✅ Builds and pushes Docker images to AWS ECR
- ✅ Automatically deploys to ECS on main branch
- ✅ Provides detailed reports and notifications

---

## Prerequisites

### 1. AWS IAM Setup (Required for Authentication)

You need to set up OIDC (OpenID Connect) for GitHub Actions to assume an AWS role:

#### A. Create an IAM Role for GitHub Actions

```bash
# 1. Go to AWS IAM Console
# 2. Providers → Add Provider
# 3. Select "OpenID Connect"
# 4. Provider URL: https://token.actions.githubusercontent.com
# 5. Audience: sts.amazonaws.com
# 6. Click "Add Provider"

# 7. Create a new IAM role:
# Name: GitHubActionsECSDeploy
# Trust Entity: Web identity (OIDC)
# Select the provider you just created
```

#### B. Add Permissions to the Role

Attach inline policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ecs:UpdateService",
        "ecs:DescribeServices",
        "ecs:DescribeTaskDefinition",
        "ecs:DescribeTasks",
        "ecs:ListTasks",
        "ecs:RegisterTaskDefinition"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "elbv2:DescribeLoadBalancers"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "iam:PassRole"
      ],
      "Resource": "arn:aws:iam::*:role/springboot-mongodb-crud-ecs-task-execution-role"
    }
  ]
}
```

### 2. Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name springboot-mongodb-crud \
  --region ap-south-2
```

### 3. Add GitHub Secrets

Go to **GitHub Repository Settings → Secrets and Variables → Actions**

Add these secrets:

| Secret Name | Value |
|-------------|-------|
| `AWS_ROLE_TO_ASSUME` | `arn:aws:iam::ACCOUNT_ID:role/GitHubActionsECSDeploy` |
| `AWS_REGION` | `ap-south-2` |

Replace `ACCOUNT_ID` with your AWS Account ID.

---

## GitHub Actions Workflow Stages

### Stage 1: Build & Test
- Checks out code
- Sets up Java 24
- Runs Maven build
- Executes unit tests
- Publishes test results

### Stage 2: Security Scan
- Scans filesystem with Trivy
- Uploads results to GitHub Security tab

### Stage 3: Docker Build & Push
- Builds Docker image
- Pushes to AWS ECR with:
  - Tag: Git commit SHA
  - Tag: `latest`

### Stage 4: Deploy (Main Branch Only)
- Renders updated ECS Task Definition
- Deploys to ECS service
- Waits for service stability
- Posts deployment comment on PR

### Stage 5: Notifications
- Creates summary of all stages
- Posts to GitHub Actions summary

---

## How It Works

### On Every Push to `main`:
```
Code → GitHub Actions Workflow Triggered
  ↓
Build & Test (Maven)
  ↓
Security Scan (Trivy)
  ↓
Docker Build & Push to ECR
  ↓
Update ECS Service
  ↓
Application Updated in AWS
```

### On Pull Requests:
```
PR Created → Build & Test runs
  ↓
Security Scan runs
  ↓
Docker image built (not deployed)
  ↓
Results posted to PR
```

---

## Monitoring Your Workflow

### 1. View Workflow Runs

Go to your GitHub repo → **Actions** tab

### 2. Check Build Status

Click on any workflow run to see:
- Build logs
- Test results
- Security scan results
- Deployment status

### 3. View Deployment Details

After successful deploy:
- Check "Deploy to AWS ECS" step for ALB URL
- Logs show deployment progression

---

## Troubleshooting

### Build Fails - Maven Error

Check:
```bash
# Local test
./mvnw clean package -DskipTests
```

### Docker Push Fails

Verify ECR repository exists:
```bash
aws ecr describe-repositories --repository-names springboot-mongodb-crud --region ap-south-2
```

### Deployment Doesn't Update

Check:
1. Are you pushing to `main` branch?
2. AWS credentials valid?
3. ECS service exists?

```bash
aws ecs describe-services \
  --cluster springboot-mongodb-crud-cluster \
  --services springboot-mongodb-crud-spring-service \
  --region ap-south-2
```

### Auth Fails

Verify OIDC role:
```bash
aws iam get-role --role-name GitHubActionsECSDeploy
```

---

## Customization

### Change Triggers

Edit `.github/workflows/deploy.yml`:

```yaml
on:
  push:
    branches: [ main, develop, staging ]  # Add more branches
  pull_request:
    branches: [ main ]
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM UTC
```

### Add Slack Notifications

Add to workflow (after Deploy step):

```yaml
- name: Notify Slack
  uses: slackapi/slack-github-action@v1
  with:
    webhook-url: ${{ secrets.SLACK_WEBHOOK }}
    payload: |
      {
        "text": "Deployment ${{ job.status }}: ${{ github.sha }}"
      }
```

### Change Docker Image Tag

Edit the `docker build` command in workflow to add version tags:

```bash
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:v1.0.0 .
```

---

## Environment Variables in Workflow

The workflow automatically sets:

| Variable | Value |
|----------|-------|
| `AWS_REGION` | `ap-south-2` |
| `ECR_REPOSITORY` | `springboot-mongodb-crud` |
| `ECS_SERVICE` | `springboot-mongodb-crud-spring-service` |
| `ECS_CLUSTER` | `springboot-mongodb-crud-cluster` |

Update these in `.github/workflows/deploy.yml` if your infrastructure differs.

---

## Next Steps

1. **Commit and push the workflow file**:
   ```bash
   git add .github/workflows/deploy.yml
   git commit -m "Add GitHub Actions CI/CD workflow"
   git push origin main
   ```

2. **Go to GitHub Actions tab** to monitor first run

3. **Fix any secrets/permissions** errors that appear

4. **Verify deployment** by checking AWS ECS console

---

## One-Time Setup Checklist

- [ ] Create OIDC provider in AWS IAM
- [ ] Create GitHub Actions IAM role
- [ ] Attach permissions policy to role
- [ ] Create ECR repository
- [ ] Add `AWS_ROLE_TO_ASSUME` secret to GitHub
- [ ] Push workflow file to main branch
- [ ] Monitor first Actions run
- [ ] Verify application updated in ECS
- [ ] Test by pushing code change to main

---

## Commands for Quick Setup

If you're doing this from command line:

```bash
# Create ECR repo
aws ecr create-repository \
  --repository-name springboot-mongodb-crud \
  --region ap-south-2

# Get your AWS Account ID
aws sts get-caller-identity --query Account --output text

# List your ECS resources to verify names
aws ecs list-clusters --region ap-south-2
aws ecs list-services --cluster springboot-mongodb-crud-cluster --region ap-south-2
```

---

**That's it!** Your CI/CD is now automated with GitHub Actions. Every push to `main` will automatically test, build, and deploy to AWS ECS.
