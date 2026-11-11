# GitHub Actions - Quick Reference

## ✅ What's Setup

Your GitHub Actions workflow (`/.github/workflows/deploy.yml`) now:

- **Builds** your Spring Boot app on every push
- **Tests** with Maven unit tests
- **Scans** for security vulnerabilities with Trivy
- **Builds** Docker image
- **Pushes** to AWS ECR
- **Deploys** to ECS (main branch only)
- **Notifies** via GitHub Actions dashboard

---

## 🚀 5-Step Setup

### 1. Create OIDC Provider (AWS)
```bash
# AWS Console → IAM → Identity Providers
# Add OpenID Connect Provider
# URL: https://token.actions.githubusercontent.com
# Audience: sts.amazonaws.com
```

### 2. Create IAM Role
```bash
# IAM → Roles → Create Role
# Trust Entity: Web identity (select OIDC provider)
# Role name: GitHubActionsECSDeploy
# Attach policy from GITHUB_ACTIONS_SETUP.md
```

### 3. Create ECR Repository
```bash
aws ecr create-repository \
  --repository-name springboot-mongodb-crud \
  --region ap-south-2
```

### 4. Add GitHub Secrets
```
Settings → Secrets → New secret

AWS_ROLE_TO_ASSUME: arn:aws:iam::ACCOUNT_ID:role/GitHubActionsECSDeploy
```

Get Account ID:
```bash
aws sts get-caller-identity --query Account --output text
```

### 5. Commit & Push
```bash
git add .github/workflows/deploy.yml
git commit -m "Add GitHub Actions workflow"
git push origin main
```

---

## 📊 Monitor Workflow

1. Go to GitHub repo
2. Click **Actions** tab
3. Click latest workflow run
4. View build logs, test results, deployment status

---

## 🔄 How It Works

```
Push to main branch
         ↓
GitHub Actions triggered
         ↓
1. Build with Maven
2. Run unit tests
3. Security scan
4. Build Docker image
5. Push to AWS ECR
6. Update ECS service
         ↓
Application updated in AWS
```

---

## ✨ What Happens on Each Push

| Branch | Action |
|--------|--------|
| `main` | Build → Test → Scan → Build Docker → Push → **Deploy** |
| `develop` | Build → Test → Scan → Build Docker → Push (no deploy) |
| PR | Build → Test → Scan (results posted to PR) |

---

## 🎯 After Setup

Every time you push code to main:
- Tests run automatically
- Docker image rebuilt
- ECS service updated
- Your app is live in AWS

No manual deployment needed!

---

## 📚 Full Setup Guide

See: `GITHUB_ACTIONS_SETUP.md` for detailed instructions

---

## ❓ Common Issues

**Build Fails?**
```bash
./mvnw clean package -DskipTests  # Test locally
```

**Docker Push Fails?**
```bash
aws ecr describe-repositories --repository-names springboot-mongodb-crud --region ap-south-2
```

**Deploy Fails?**
- Check AWS credentials in secrets
- Verify OIDC role has correct permissions
- Check ECS service exists

---

## 🧪 Test It

1. Make a small code change
2. Push to main
3. Go to GitHub Actions tab
4. Watch build complete
5. See deployment happen automatically

That's it! CI/CD is now live.
