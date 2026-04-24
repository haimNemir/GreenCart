# GreenCart

## Bringing up the infrastructure

### Prerequisites (one-time, before the first run)

```bash
# Generate the SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/greencart-key

# Authenticate the GitHub CLI with a Fine-grained PAT
# (scope: GreenCart repo only, permission: Repository secrets — read/write)
echo "<token>" | gh auth login --with-token
```

---

### Option A — via script (recommended)

```bash
./scripts/build-infra.sh
```

The script handles everything: S3/DynamoDB backend, all AWS infrastructure, and all GitHub Actions secrets.
After it completes, push to `main` to trigger the first CI/CD deploy.

---

### Option B — step by step (manual)

**1. Provision the state backend**

```bash
cd bootstrap/
terraform init
terraform apply
```

**2. Provision all AWS infrastructure**

```bash
cd terraform/
terraform init
terraform apply -var="public_key=$(cat ~/.ssh/greencart-key.pub)"
```

**3. Set GitHub Actions secrets**

```bash
IP1=$(terraform output -raw app_instance_1_ip)
IP2=$(terraform output -raw app_instance_2_ip)
MONGO=$(terraform output -raw mongo_private_ip)
ROLE=$(terraform output -raw github_actions_role_arn)

gh secret set EC2_APP_IP_1       --repo haimNemir/GreenCart --body "$IP1"
gh secret set EC2_APP_IP_2       --repo haimNemir/GreenCart --body "$IP2"
gh secret set MONGO_URL          --repo haimNemir/GreenCart --body "mongodb://${MONGO}:27017"
gh secret set AWS_ROLE_ARN       --repo haimNemir/GreenCart --body "$ROLE"
gh secret set EC2_SSH_PRIVATE_KEY --repo haimNemir/GreenCart < ~/.ssh/greencart-key
```

**4. Trigger the first deploy**

Push to `main` — GitHub Actions builds the images, pushes to ECR, and deploys to both EC2 instances.

---

## SSH access

Get the IPs from Terraform (run from `terraform/`): `terraform output`

Add to `~/.ssh/config` once:

```
Host greencart-app1
    HostName <APP_INSTANCE_1_IP>
    User ec2-user
    IdentityFile ~/.ssh/greencart-key

Host greencart-app2
    HostName <APP_INSTANCE_2_IP>
    User ec2-user
    IdentityFile ~/.ssh/greencart-key

Host greencart-db
    HostName <MONGO_PRIVATE_IP>
    User ec2-user
    IdentityFile ~/.ssh/greencart-key
    ProxyJump greencart-app1
```

Then connect with: `ssh greencart-app1` / `ssh greencart-app2` / `ssh greencart-db`

To open a MongoDB shell: `docker exec -it $(docker ps -q) mongosh greencart`