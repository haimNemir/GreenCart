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

The script handles everything: S3/DynamoDB backend, all AWS infrastructure, GitHub Actions secrets,
and the first CI/CD deploy. The application is live when the script completes.

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

```bash
gh workflow run ci.yml --repo haimNemir/GreenCart --ref main
```

GitHub Actions builds the images, pushes to ECR, and deploys to both EC2 instances.

---

## Networking & Traffic Routing

### Inbound request — user to app

```
User browser
  ↓
ALB (port 80, public) — single DNS entry, distributes across both app instances
  ↓
App EC2 (port 80) — security group accepts traffic from ALB SG only
  ↓
Docker port mapping (ports: "80:80") — host port 80 forwarded into the container
  ↓
frontend container — Nginx listening on port 80
  ├── location /        → serves static React build from /usr/share/nginx/html
  ├── location /api/    → proxy_pass http://backend:3000  (via app-net bridge)
  └── location /health  → proxy_pass http://backend:3000/health (via app-net bridge)
```

Nginx and Express communicate over the internal Docker bridge network (`app-net`) using the
container name `backend` as the hostname — no port is exposed to the host for Express.

---

### App instances → DB

```
App EC2 (private IP, app-sg)
  ↓
VPC local route — all traffic within the VPC CIDR is routed internally, no gateway needed
  ↓
DB EC2 (private IP, db-sg) — security group accepts port 27017 from app-sg only
  ↓
MongoDB container (port 27017)
```

---

### DB outbound — pulling Docker images from the internet

The DB instance lives in a private subnet with no public IP. Outbound internet access is
provided by the NAT Gateway.

```
DB instance (private IP e.g. 10.0.3.5)
  ↓
Private Route Table: 0.0.0.0/0 → NAT Gateway
  ↓
NAT Gateway: replaces source IP 10.0.3.5 with its Elastic IP (e.g. 54.x.x.x)
  ↓
Public Route Table: 0.0.0.0/0 → Internet Gateway
  ↓
IGW: maps the EIP to the NAT Gateway and forwards the packet out
  ↓
Internet (DockerHub / GitHub)
```

The return traffic follows the same path in reverse. The internet never initiates a connection
to the DB — the NAT Gateway drops all unsolicited inbound packets.

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

# The DB is in a private subnet — its security group accepts SSH only from the
# app security group. ProxyJump through an app instance is the only way in.
Host greencart-db
    HostName <MONGO_PRIVATE_IP>
    User ec2-user
    IdentityFile ~/.ssh/greencart-key
    ProxyJump greencart-app1
```

Then connect with: `ssh greencart-app1` / `ssh greencart-app2` / `ssh greencart-db`

To open a MongoDB shell: `docker exec -it $(docker ps -q) mongosh greencart`