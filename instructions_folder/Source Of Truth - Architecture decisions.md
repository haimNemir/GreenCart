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
      └── GET /api/*      → proxies to Express (internal Docker network)
                                └── Express handles the route
                                └── Express queries MongoDB
                                └── Express returns JSON
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

The CI pipeline is responsible for:
- installing dependencies
- running build and validation steps
- building **two Docker images**: the backend image and the frontend (nginx) image

The CD pipeline is responsible for:
- pushing **both Docker images** to **Amazon ECR** (one repository per image)
- SSHing into **each of the two application EC2 instances** and on each:
  - pulling the updated images: `docker compose pull`
  - redeploying the updated containers: `docker compose up -d`

The deployment must run on both application EC2 instances to keep them in sync. Deploying to only one instance would leave the other running the previous version.

This CI/CD design was chosen in order to keep the project simple, practical, and aligned with the selected AWS-based architecture, without introducing Kubernetes.


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
| Backend instances SG | 80 | HTTP | ALB SG | nginx — ALB health checks and traffic |
| Backend instances SG | 22 | SSH | Admin IP | Direct admin access |
| DB instance SG | 27017 | TCP | Backend instances SG | MongoDB application access |
| DB instance SG | 22 | SSH | Backend instances SG | Admin jump host access |

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

The exact MongoDB image version is still not decided.
Version selection will be finalized later together with the rest of the project resource versions.

However:
- **`latest` will not be used**


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

The public visibility means no authentication is required to clone the repository — this is relevant for the MongoDB EC2 `user_data` provisioning script, which clones the repo on first boot without any credentials.

### Architecture Flow:
**Client -> ALB (public subnet) -> nginx Container on Application EC2 (public subnet, port 80) -> [static files served directly] OR [/api/* proxied to Express Container (internal Docker network)] -> MongoDB Container on dedicated DB EC2 instance (private subnet)**

Left to decide:
- Work tree files platform.
- Priority list of what is important to implement first in this project, and what can wait for later.
- Decide which version of each element, resource, library, or extension in our project, so that conflicts will not exist.
