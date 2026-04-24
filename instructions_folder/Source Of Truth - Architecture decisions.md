## Important note:
The "Source Of Truth - Architecture decisions" file is the final document that contains all the architectural decisions of this project.
If you want to change anything in this file, you must receive explicit approval from me.
When we change something in the overall architecture, you should document the change there—even if the change is not yet complete—so that the current state of the change is always recorded.

## Selected Technology Stack

- **Backend:** Node.js with TypeScript and Express
- **Frontend:** HTML and plain JavaScript (`app.js`)
- **Frontend Server:** nginx
- **Database:** MongoDB
- **Infrastructure as Code:** Terraform
- **Cloud Platform:** AWS
- **Deployment Model:** Container-based architecture
- **Load Balancer:** AWS Application Load Balancer (ALB)
- **CI/CD:** GitHub Actions + Amazon ECR + Docker Compose-based automated deployment to Red Hat Enterprise Linux 9.3 hosts


### Linux Runtime Notes:
The project runtime environment will use:
- **Red Hat Enterprise Linux 9.3**

This is the selected Linux distribution for the project infrastructure.

### Backend Notes:
Express is used as the backend web framework in order to:
- define API routes
- handle HTTP requests and responses

Express does **not** serve static frontend files. That responsibility belongs to the nginx container.

### Frontend Notes:
The frontend is intentionally kept simple.
It uses plain HTML and JavaScript without a frontend framework and without TypeScript.

All API calls in the frontend JavaScript must use **relative paths** (e.g., `/api/items`) so that nginx can proxy them correctly to the backend container.


### Container Architecture Notes:
The project uses **three separate containers**, each running a single component:

- **Container 1 — nginx (frontend):** serves static HTML and JavaScript files, acts as the public entry point
- **Container 2 — Node.js / Express (backend):** handles API routes and database access, not reachable directly from outside
- **Container 3 — MongoDB (database):** runs on a dedicated EC2 instance, separate from the application EC2 instances

This design was chosen in order to comply with the project requirement that every component runs in its own container.

The routing flow inside each application EC2 instance is:

```
ALB
 └── nginx (port 80)
      ├── GET /           → serves index.html directly
      ├── GET /app.js     → serves app.js directly
      ├── GET /api/*      → proxies to Express (internal Docker network)
      │                         └── Express handles the route
      │                         └── Express queries MongoDB
      │                         └── Express returns JSON
      └── GET /health     → proxies to Express (internal Docker network)
                                └── Express returns 200 OK
```

nginx is the only container that is publicly reachable. Express is only reachable from nginx over the internal Docker Compose network.

CORS configuration is **not required** because all client requests go through nginx on the same origin.


### nginx Container Notes:
The nginx container will use:
- **a custom nginx Dockerfile**
- the static HTML and JavaScript files are **baked into the image at build time** using a `COPY` instruction

This means the frontend image is a versioned, self-contained artifact — consistent with the CI/CD philosophy of the project.

The nginx container is responsible for:
- serving static files directly
- proxying `/api/*` requests to the Express container
- proxying `/health` requests to the Express container (for ALB health check purposes)

The nginx container is **not** based on a volume mount of files from the host at runtime.

nginx was chosen as the frontend container over Express for two reasons:
- **Performance:** nginx is purpose-built for serving static files and handling HTTP traffic. It is significantly faster and more efficient than Express for this use case, as it operates at a lower level without the overhead of a JavaScript runtime.
- **Separation of concerns:** nginx is a web server designed to be the public-facing entry point. Express is an application server designed to run business logic. Putting nginx in front and Express behind matches the natural role of each tool. Using Express as the entry point that proxies to a separate static file container would reverse this layering and make Express responsible for HTTP routing — a job it was not designed for.


### Load Balancer Notes:
The project includes an **AWS Application Load Balancer (ALB)** as part of the bonus architecture scope.

The ALB is responsible for:
- acting as the public entry point of the application
- routing incoming HTTP/HTTPS traffic to the **nginx containers** on the application EC2 instances


### Listener Notes:
The ALB will use:
- **1 HTTP listener**
- **port 80**

The listener will use:
- **a default forward action**
- to send incoming traffic to the backend target group

This is the minimal listener configuration selected for the project at the current stage.

### Health Check Notes:
The ALB target group will use:
- **a minimal HTTP health check**

The selected health check configuration is:
- **Protocol:** HTTP
- **Path:** `/health`
- **Expected response:** `200 OK`

The health check request flow is:
```
ALB → nginx (/health) → proxied to Express → 200 OK
```

This design was chosen so that the ALB confirms the full application stack is alive (nginx + Express), not just that nginx is running.

This requires the Express backend to expose a dedicated health endpoint:

```ts
app.get('/health', (req, res) => {
  res.status(200).send('OK')
})
```

This also affects the security group configuration:
- the application instances must allow inbound traffic from the ALB security group on **port 80** (nginx)
- the Express application port is only reachable internally via the Docker Compose network and does not require an inbound security group rule from the ALB

This is the minimal health check configuration selected for the project at the current stage.

### CI/CD Notes:
The project will use **GitHub Actions** for CI/CD.

**Workflow file:** `.github/workflows/ci.yml`

**Triggers:**
- `pull_request` targeting `main` — runs build + smoke tests only. No ECR push, no deploy. The OIDC role blocks AWS access from PRs by design.
- `push` to `main` — runs the full pipeline: build → smoke tests → ECR push → rolling deploy to both EC2 instances.
- `push` of a `v*.*.*` tag — runs build → smoke tests → ECR push with a version tag (e.g. `1.2.3`). No deploy — versioned tags are for image versioning only.

**Image tagging strategy:**
- Every push creates an image tagged `sha-<7-char-commit-hash>` (e.g. `sha-abc1234`).
- Tag pushes additionally create a version tag (e.g. `1.2.3`) on the same image.

**Smoke tests (run on all triggers, before any ECR push):**
- Backend: spins up a `mongo:7.0` container and the backend container on a shared Docker network (`ci-net`). Curls `http://localhost:3000/health` in a loop until `200 OK`. MongoDB is required because the backend calls `process.exit(1)` if the connection fails — it cannot be tested in isolation.
- Frontend: starts the frontend container and curls `http://localhost:8080/` to confirm nginx serves static files. No backend needed — the smoke test only hits `/`.

**Deployment strategy — sequential rolling deploy:**
1. Deploy to instance 1: SSH in, ECR login, `docker compose pull`, `docker compose up -d`.
2. Wait for instance 1: SSH in and curl `http://localhost/health` in a loop (30 attempts × 5 s). Only proceeds when healthy.
3. Deploy to instance 2: same as instance 1.
4. Wait for instance 2: same health check loop.

This ensures the ALB always has at least one healthy instance during deployment — zero downtime.

**ECR URL construction:** The workflow derives the AWS account ID dynamically via `aws sts get-caller-identity` after the OIDC step. No hardcoded account ID anywhere in the workflow.

**Required GitHub Actions secrets (all set automatically by `build-infra.sh`):**
- **`EC2_SSH_PRIVATE_KEY`** — private key used to SSH into both application EC2 instances
- **`EC2_APP_IP_1`** and **`EC2_APP_IP_2`** — Elastic IPs of the two application EC2 instances
- **`MONGO_URL`** — MongoDB connection string (e.g. `mongodb://<private-ip>:27017`)
- **`AWS_ROLE_ARN`** — ARN of the GitHub Actions IAM role used for OIDC authentication with AWS

All five secrets are set automatically by `build-infra.sh` after `terraform apply` completes.

This CI/CD design was chosen in order to keep the project simple, practical, and aligned with the selected AWS-based architecture, without introducing Kubernetes.


### Docker Compose File Structure Notes:
The project uses **two separate Docker Compose files**, one per EC2 role:

- **`docker-compose.app.yml`** — used on the application EC2 instances. Defines the nginx and Express containers.
- **`docker-compose.db.yml`** — used on the MongoDB EC2 instance. Defines the MongoDB container and the seed script volume mount. Downloaded via `curl` from the public GitHub repository as part of the `user_data` provisioning script.

This separation ensures each EC2 instance only knows about the services it runs. There is no risk of accidentally starting the wrong services on the wrong machine.

### Validation Notes:
The project will use:
- **CI/CD-based automated validation**

Validation checks will be executed through:
- **a dedicated validation script stored in the repository**

The CI/CD pipeline will use this script as the main validation entry point.

The validation script will verify the mandatory project behavior, including:
- backend health availability
- backend access to the seeded database data
- the required application response flow
- the frontend behavior required by the exercise

No separate standalone validation implementation is planned outside this repository-based validation script and its CI/CD execution flow.

### Compute Notes:
The application layer will run on **two separate EC2 instances** registered as ALB targets.

Each application EC2 instance runs:
- the nginx container (frontend)
- the Express container (backend)

The selected instance type for the application instances is:
- **t3.micro**

MongoDB will run on:
- **one dedicated EC2 instance**
- separate from the application EC2 instances
- placed in the **private subnet**
- instance type: **t3.micro** — sufficient for this exercise given the minimal dataset (4 documents)

### Network Design Notes:
The subnet placement for each component was decided as follows:

| Component | Subnet | Reason |
|---|---|---|
| ALB | Public | Must be internet-facing by design |
| Application EC2 instances (nginx + Express) | Public | Requires direct SSH access from admin IP; less sensitive (holds no data) |
| MongoDB EC2 instance | Private | Contains the actual application data; must be fully isolated from the internet |

The application EC2 instances remain in public subnets because:
- SSH access (port 22) is required for administration
- Moving them to a private subnet would require a bastion host


The MongoDB EC2 instance is placed in a private subnet because:
- It is the most sensitive component in the architecture
- Private subnet isolation means it is unreachable from the internet at the **network level**, regardless of security group configuration
- This provides a second layer of defense: even a misconfigured inbound rule cannot expose the database

The NAT Gateway is required because:
- Instances in the private subnet have no direct route to the internet
- The MongoDB EC2 needs outbound internet access to pull the official MongoDB Docker image
- NAT Gateway allows outbound-only internet access from the private subnet

The NAT Gateway requires its own dedicated Elastic IP. This is how it works:
the MongoDB EC2 has only a private IP and cannot communicate directly with the internet.
When it needs to reach the internet (e.g., `docker pull`), it sends the request to the NAT Gateway.
The NAT Gateway substitutes the private IP with its own public Elastic IP and forwards the request on behalf of the MongoDB EC2.
The response returns to the NAT Gateway, which forwards it back to the MongoDB EC2 over the private network.
The MongoDB EC2 is never exposed to the internet — only the NAT Gateway's Elastic IP is visible externally.
This is an AWS hard requirement: a NAT Gateway cannot be created without an Elastic IP assigned to it.

### Storage Notes:
All EC2 instances will use:
- **EBS root volumes**

The MongoDB EC2 instance will also use:
- **its EBS root volume** for storage in the current minimal design

### AWS Infrastructure Notes:
The minimal AWS infrastructure for this project includes:
- **1 VPC**
- **1 Internet Gateway**
- **2 public subnets** across **2 Availability Zones** (ALB + application EC2 instances)
- **1 private subnet** (MongoDB EC2 instance)
- **1 NAT Gateway** (placed in a public subnet — enables outbound internet access from the private subnet)
- **2 route tables:**
  - 1 public route table: `0.0.0.0/0 → Internet Gateway`
  - 1 private route table: `0.0.0.0/0 → NAT Gateway`
- **3 Elastic IPs** — one per application EC2 instance (×2) + one for the NAT Gateway (×1)
- **1 Application Load Balancer**
- **1 target group**

Security will be separated using:
- **1 security group for the ALB**
- **1 security group for the backend instances**
- **1 security group for the DB instance**

Security group inbound rules:

| Security Group | Port | Protocol | Source | Purpose |
|---|---|---|---|---|
| ALB SG | 80 | HTTP | `0.0.0.0/0` | Public web traffic |
| Application instances SG | 80 | HTTP | ALB SG | nginx — ALB health checks and traffic |
| Application instances SG | 22 | SSH | Admin IP | Direct admin access |
| DB instance SG | 27017 | TCP | Application instances SG | MongoDB application access |
| DB instance SG | 22 | SSH | Application instances SG | Admin jump host access |

The container registry design is:
- **1 Amazon ECR repository** for the backend (Express) image
- **1 Amazon ECR repository** for the frontend (nginx) image

No dedicated ECR repository will be created for:
- **MongoDB**


### MongoDB Image Notes:
The project will not use a dedicated ECR repository for MongoDB in the minimal architecture.

Instead, the MongoDB container will use:
- **the official MongoDB image**

This decision was made because using a custom MongoDB image would require embedding the `docker-compose.yml` and the database seed script via `COPY` at build time. This would create an ongoing maintenance burden: every time the official MongoDB image releases an update, the custom image would need to be rebuilt and pushed to keep up. That requires a dedicated CI pipeline and a separate ECR repository just for the database image.

By using the official image instead, MongoDB updates are handled simply by pulling a newer tag from Docker Hub — no rebuild, no pipeline, no extra repository. The `docker-compose.yml` and seed script are pulled directly from the project's GitHub repository onto the MongoDB EC2 host at provisioning time using `curl`.

The selected MongoDB image version is:
- **`mongo:7.0`** — current LTS release

`latest` is not used. The version is pinned for deterministic, reproducible provisioning.


### Database Initialization Notes:
The project will use:
- **the official MongoDB image**
- **a repository-managed MongoDB initialization script**
- mapped into **`/docker-entrypoint-initdb.d`**

This initialization approach is part of the mandatory project scope and will be used to create the required base dataset for:
- apples
- bananas
- oranges
- avocados

This seed mechanism is selected because it keeps the architecture simple and allows the database to be initialized automatically as part of the scripted project setup.

The database seed process is intended for:
- **first-time database initialization**

The startup order of the project must respect the following dependency flow:
1. the MongoDB container starts
2. the database initialization script is executed on first-time startup
3. the backend starts and uses the seeded data
4. the validation flow runs only after the application is ready

The seed data and initialization logic will be stored in the same Git repository as the rest of the project source code and automation.

### MongoDB Provisioning Notes:
The MongoDB EC2 instance has no CI/CD pipeline of its own. It is fully self-provisioning via a **Terraform `user_data` script** that runs automatically on first boot.

`user_data` is a built-in AWS EC2 feature that allows you to attach a shell script to any instance at launch time. The script runs automatically the first time the instance boots. It is defined directly inside the Terraform `aws_instance` resource and requires no external tools.



The `user_data` script is responsible for:
1. Installing Docker and Docker Compose
2. Using `curl` to download only the required files from the public GitHub repository: the `docker-compose.yml` and the database seed script (outbound internet access is available via the NAT Gateway — no authentication required as the repository is public)
3. Running `docker compose up -d` to start the MongoDB container

On first container startup, MongoDB automatically executes the initialization script mapped into `/docker-entrypoint-initdb.d`, which seeds the required base dataset.

This means the full MongoDB provisioning flow is:
```
terraform apply
  └── EC2 instance created (private subnet)
       └── user_data runs on first boot
            └── Docker + Docker Compose installed
            └── curl downloads docker-compose.yml + seed script from GitHub
            └── docker compose up -d
                 └── MongoDB container starts
                 └── Initialization script runs (first boot only)
                 └── Database seeded and ready
```

No manual steps are required after `terraform apply`. The MongoDB instance is fully operational as part of the infrastructure provisioning flow.

### IAM Notes:
The project will use:
- **1 GitHub OIDC provider** connected to AWS
- **1 IAM role for GitHub Actions** in order to push images to both ECR repositories and perform deployment actions
- **1 instance profile / IAM role for the application EC2 instances** in order to support ECR image pulls for both images


### Instance Access Notes:
The project will use:
- **SSH**
- **EC2 key pairs**

for direct access to the application EC2 instances.

SSM will not be used in this architecture.

Each application EC2 instance is assigned an **Elastic IP** so that its public IP address remains fixed across stop/start cycles. This is required because the CI/CD pipeline SSHes to both instances by IP — dynamic IPs would break the pipeline after any restart.

The Elastic IPs are exposed as Terraform outputs and stored as GitHub Actions secrets.

This directly affects the security group design:
- the application instances must allow inbound **SSH (port 22)** only from the approved administrator IP
- the DB instance does **not** allow inbound SSH from the internet, but **does** allow inbound SSH (port 22) from the backend instances security group

This decision also affects IAM design:
- no SSM-specific instance access configuration is required

### Admin Access to MongoDB Notes:
The MongoDB EC2 instance is in a private subnet and has no direct SSH access from the internet. Admin access follows a **two-hop jump host pattern**:

```
Admin machine
  └── SSH → Application EC2 (public subnet, Elastic IP)
                └── SSH → MongoDB EC2 (private subnet, private IP)
                              └── docker exec → MongoDB shell
```

This requires:
- SSH agent forwarding enabled on the admin machine (`ssh -A`)
- The MongoDB EC2 security group allows inbound SSH (port 22) from the backend instances security group
- The same EC2 key pair is used for both hops — the MongoDB EC2 is launched with the same key pair as the application EC2 instances. The private key never leaves the admin machine; SSH agent forwarding passes the authentication through transparently.

This pattern gives the admin full shell access to the MongoDB EC2, including the ability to run `docker exec` into the MongoDB container for direct database operations.

### Application Instance IAM Notes:
The application EC2 instances will use an instance profile / IAM role in the current architecture.

This decision is based on the following:
- the backend and frontend containers will pull their images from Amazon ECR
- the deployment flow depends on AWS-managed container image access for both images

The instance IAM role is required only for the AWS access that supports this deployment design.


### Repository Notes:
The project will use:
- **one Git repository**
- the repository is **public**

All source code, infrastructure code, deployment logic, and automation scripts will be stored in the same repository.

The public visibility means no authentication is required to clone the repository — this is relevant for the MongoDB EC2 `user_data` provisioning script, which downloads the required files via curl on first boot without any credentials.

### AWS Region Notes:
All resources in this project are deployed to:
- **AWS region: `us-east-1`** (US East — N. Virginia)

All Terraform provider configuration and resource deployments target this region exclusively.


### Resource Versions Notes:
The following versions are pinned across the entire project to ensure compatibility and avoid unexpected breakage from upstream changes:

| Component | Pinned version | Notes |
|---|---|---|
| MongoDB | `mongo:7.0` | Current LTS — stable, long-term support |
| Node.js (backend base image) | `node:20-alpine` | LTS ("Iron") — `alpine` keeps the image small |
| nginx (frontend base image) | `nginx:1.26-alpine` | Current stable branch — `alpine` for size |
| Terraform | `~> 1.9` | Recent stable, no breaking changes expected |
| AWS Terraform provider | `~> 6.0` | Matches the Calculator project for consistency |

`latest` is not used for any resource. The goal is deterministic builds: the same version runs locally, in CI, and on every EC2 instance.


### Terraform State Backend Notes:
The project uses **Amazon S3 + DynamoDB** as the Terraform remote state backend.

| Resource | Name |
|---|---|
| S3 bucket | `greencart-tfstate-haimnemir` |
| DynamoDB table | `greencart-tfstate-lock` |

The S3 bucket stores the `terraform.tfstate` file. The DynamoDB table provides state locking to prevent concurrent modifications.

The state backend is provisioned by the **`bootstrap/`** Terraform configuration, which is a separate Terraform workspace from the main infrastructure. It is applied once at the beginning of `build-infra.sh`, before the main infrastructure is initialized.

The S3 bucket is configured with **`force_destroy = true`**, which allows Terraform to empty and delete the bucket in a single `terraform destroy` operation — required for the full teardown flow.

**Destroy order (critical — must not be reversed):**
1. Main infrastructure is destroyed first (`terraform destroy` in `terraform/`) — state is still readable from S3 at this point
2. S3 bucket is emptied automatically via `force_destroy`
3. Bootstrap infrastructure is destroyed (`terraform destroy` in `bootstrap/`) — S3 bucket and DynamoDB table are deleted

This full teardown is intentional. The project requirement is "provision from scratch," meaning all infrastructure — including the state backend — must be destroyable and rebuildable with no manual steps.


### Admin IP Notes:
SSH access to the application EC2 instances is restricted to the administrator's current public IP address. This is implemented as a Terraform variable:

- **Variable name:** `var.admin_cidr`
- **Format:** CIDR notation, e.g. `1.2.3.4/32`

The `build-infra.sh` script auto-detects the current public IP at run time using `curl -s ifconfig.me` and passes it directly to Terraform. No manual input is required.

Home ISP IPs are dynamic and may change between sessions. Auto-detection ensures the security group always reflects the current IP without any manual action.


### SSH Key Pair Notes:
The EC2 key pair is created via Terraform using the `aws_key_pair` resource. This satisfies project requirement #6 (all architecture defined as IaC) because the AWS key pair resource itself is fully defined in Terraform and committed to GitHub.

**Key generation — one-time manual step, run once before the first `build-infra.sh`:**
```
ssh-keygen -t ed25519 -f ~/.ssh/greencart-key
```

This produces:
- `~/.ssh/greencart-key` — private key (stays on the admin machine)
- `~/.ssh/greencart-key.pub` — public key (read by Terraform)

**How Terraform uses the key:**
- The `build-infra.sh` script reads `~/.ssh/greencart-key.pub` automatically
- Terraform creates the `aws_key_pair` resource using the public key
- All EC2 instances are launched with this key pair
- The private key never enters Terraform state

**Who uses the private key:**

| Party | Purpose |
|---|---|
| Admin (you) | Direct SSH into application EC2 instances for maintenance |
| Admin (you) | Two-hop SSH: app EC2 → MongoDB EC2 (jump host pattern) |
| GitHub Actions | SSH into both app EC2 instances to pull images and redeploy containers |

The private key is stored in exactly two places:
1. `~/.ssh/greencart-key` — on the admin machine
2. `EC2_SSH_PRIVATE_KEY` — as a GitHub Actions secret (set automatically by `build-infra.sh`)


### Terraform Folder Structure Notes:
The Terraform code is split into two separate workspaces and organized into modules:

```
GreenCart/
├── bootstrap/               ← Terraform workspace: S3 bucket + DynamoDB (run first, once)
│   ├── provider.tf
│   ├── locals.tf
│   ├── s3.tf
│   ├── dynamodb.tf
│   └── outputs.tf
├── terraform/               ← Terraform workspace: main infrastructure
│   ├── modules/
│   │   ├── vpc/             ← VPC, subnets, IGW, NAT Gateway, route tables
│   │   ├── security_groups/ ← ALB SG, application instances SG, DB instance SG
│   │   ├── ecr/             ← Two ECR repositories (backend + frontend)
│   │   ├── iam/             ← GitHub OIDC provider, GH Actions role, EC2 instance profile
│   │   ├── ec2_app/         ← Two application EC2 instances, Elastic IPs, key pair
│   │   ├── ec2_db/          ← MongoDB EC2 instance (private subnet, user_data)
│   │   └── alb/             ← ALB, target group, listener
│   ├── main.tf              ← Root module: calls all child modules, wires inputs/outputs
│   ├── variables.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── backend.tf           ← S3 remote state backend configuration
├── scripts/
│   ├── build-infra.sh
│   └── destroy-infra.sh
├── backend/
├── frontend/
├── mongo/
└── docker-compose files
```

Each module folder contains its own `main.tf`, `variables.tf`, and `outputs.tf`. The root `main.tf` calls all modules and wires their inputs and outputs together.


### Scripts Notes:
The project uses two shell scripts for full lifecycle management. Running either script requires no additional manual steps.

**`build-infra.sh` — full provisioning from scratch:**
1. Runs `terraform apply` in `bootstrap/` — creates S3 bucket and DynamoDB table
2. Runs `terraform init` in `terraform/` — initializes with the S3 backend
3. Auto-detects current admin IP via `curl -s ifconfig.me`
4. Reads SSH public key from `~/.ssh/greencart-key.pub`
5. Runs `terraform apply` in `terraform/` — provisions all AWS infrastructure
6. Reads Terraform outputs (Elastic IPs of both application EC2 instances)
7. Sets the following GitHub Actions secrets automatically via the `gh` CLI:
   - `EC2_APP_IP_1` and `EC2_APP_IP_2` — Elastic IPs from Terraform outputs
   - `MONGO_URL` — MongoDB connection string from Terraform outputs
   - `EC2_SSH_PRIVATE_KEY` — private key read from `~/.ssh/greencart-key`
   - `AWS_ROLE_ARN` — GitHub Actions IAM role ARN from Terraform outputs

**`destroy-infra.sh` — full teardown to zero:**
1. Runs `terraform destroy` in `terraform/` — tears down all main infrastructure (state is still readable from S3 at this point)
2. Runs `terraform destroy` in `bootstrap/` — `force_destroy` empties the S3 bucket, then both S3 and DynamoDB are deleted

After `destroy-infra.sh` completes, the AWS account is in exactly the same state as before `build-infra.sh` was ever run. The full provisioning flow can be repeated cleanly.

**Prerequisite — run once before the first `build-infra.sh`:**
- Generate the SSH key pair: `ssh-keygen -t ed25519 -f ~/.ssh/greencart-key`
- Authenticate the GitHub CLI: `gh auth login --with-token` using a Fine-grained PAT (see below)

**`gh` CLI authentication:**
`gh` is needed only to set GitHub Actions secrets via the GitHub API (`gh secret set`). A Fine-grained PAT is used instead of a full OAuth login to limit the blast radius if the token is ever exposed.

Token configuration:
- **Scope:** GreenCart repository only
- **Permission:** Repository secrets — Read and write (no other permissions)
- **Expires:** Tue, Jun 23 2026

To authenticate: `echo "<token>" | gh auth login --with-token` (run inside WSL)


### Architecture Flow:
**Client -> ALB (public subnet) -> nginx Container on Application EC2 (public subnet, port 80) -> [static files served directly] OR [/api/* proxied to Express Container (internal Docker network)] -> MongoDB Container on dedicated DB EC2 instance (private subnet)**

### Left to decide:
- Nothing currently open. All known decisions have been documented above.


### Recommended Build Order (nice to have — follow if circumstances allow):

The goal of this order is to avoid any situation where infrastructure is built one way and then rewritten when bonus features are added. Each phase should be additive only.

**Phase 1 — Application core (local, no cloud)**
- Express backend: API routes + `/health` endpoint
- MongoDB seed script + `docker-compose.db.yml`
- Frontend: `index.html` + `app.js`
- Dockerfiles for backend (Express) and frontend (nginx)
- `docker-compose.app.yml` (nginx + Express)
- Local end-to-end test — verify the full stack works before touching AWS

**Phase 2 — Full AWS infrastructure (Terraform) — built in final form, including ALB**
- VPC, 2 public subnets, 1 private subnet, IGW, NAT Gateway, route tables
- Security groups (ALB SG, Application instances SG, DB instance SG)
- ECR repositories (backend + frontend)
- IAM: GitHub OIDC, IAM role for GH Actions, instance profile for app EC2s
- MongoDB EC2 (private subnet, `user_data` self-provisioning)
- Application EC2 instances ×2 (public subnet, Elastic IPs, SSH key pair)
- ALB, target group, and listener — included here because the security groups are designed around the ALB from day one; adding it later would require rewriting existing security group rules rather than adding new resources

**Phase 3 — Deployment scripts**
- `build-infra` — provisions everything from scratch
- `destroy-infra` — tears everything down completely

**Phase 4 — Bonus: CI/CD pipeline (purely additive)**
- GitHub Actions (build images → push to ECR → deploy to both EC2s)
- Does not modify any existing Terraform resources

**Phase 5 — Bonus: README (purely additive)**


### Left to do:
- **Phase 5:** Write the README.