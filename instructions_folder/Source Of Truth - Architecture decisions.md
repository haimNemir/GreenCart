## Important note:
The “Source Of Truth - Architecture decisions” file is the final document that contains all the architectural decisions of this project.
If you want to change anything in this file, you must receive explicit approval from me.
When we change something in the overall architecture, you should document the change there—even if the change is not yet complete—so that the current state of the change is always recorded.

## Selected Technology Stack

- **Backend:** Node.js with TypeScript and Express
- **Frontend:** HTML and plain JavaScript (`app.js`)
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
- serve static frontend files when required

### Frontend Notes:
The frontend is intentionally kept simple.
It uses plain HTML and JavaScript without a frontend framework and without TypeScript.


### Frontend and Backend Container Notes:
The frontend and backend will run in:
- **one shared application container**

In the current architecture:
- the backend will expose the application logic and API
- the frontend will be served as static files by the same application container

This means the frontend is not treated as a separate runtime component in the current project scope.

A future bonus improvement may separate the frontend and backend into different containers.

However:
- this is not part of the current architecture decision
- the project architecture must be designed and implemented around a single shared application container

### Load Balancer Notes:
The project includes an **AWS Application Load Balancer (ALB)** as part of the bonus architecture scope.

The ALB is responsible for:
- acting as the public entry point of the application
- routing incoming HTTP/HTTPS traffic to the backend service


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

This requires the backend application to expose a dedicated health endpoint, for example:

```ts
app.get('/health', (req, res) => {
  res.status(200).send('OK')
})
```

This also affects the security group configuration:
- the backend instances must allow inbound traffic from the ALB security group on the application port
- the health check traffic will use the same allowed path through that application port

This is the minimal health check configuration selected for the project at the current stage.

### CI/CD Notes:
The project will use **GitHub Actions** for CI/CD.

The CI pipeline is responsible for:
- installing dependencies
- running build and validation steps
- building Docker images

The CD pipeline is responsible for:
- pushing Docker images to **Amazon ECR**
- pulling the updated images on the AWS Linux host
- redeploying the updated containers using **Docker Compose**
- updating the running containers automatically

The selected CD approach is based on:
- `docker compose pull`
- `docker compose up -d`

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
The backend layer will run on **two separate EC2 instances** registered as ALB targets.

The selected instance type for the backend target instances is:
- **t3.micro**

MongoDB will run on:
- **one dedicated EC2 instance**
- separate from the backend target instances

### Storage Notes:
All EC2 instances will use:
- **EBS root volumes**

The MongoDB EC2 instance will also use:
- **its EBS root volume** for storage in the current minimal design

### AWS Infrastructure Notes:
The minimal AWS infrastructure for this project includes:
- **1 VPC**
- **1 Internet Gateway**
- **2 public subnets** across **2 Availability Zones**
- **1 route table**
- **1 Application Load Balancer**
- **1 target group**

Security will be separated using:
- **1 security group for the ALB**
- **1 security group for the backend instances**
- **1 security group for the DB instance**

The container registry design is:
- **1 Amazon ECR repository** for the backend image only

No dedicated ECR repository will be created for:
- **MongoDB**


### MongoDB Image Notes:
The project will not use a dedicated ECR repository for MongoDB in the minimal architecture.

Instead, the MongoDB container will use:
- **the official MongoDB image**

This decision was made in order to:
- keep the architecture minimal
- avoid maintaining a separate image repository for the database
- avoid adding unnecessary CI/CD steps for the database container

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

### IAM Notes:
The project will use:
- **1 GitHub OIDC provider** connected to AWS
- **1 IAM role for GitHub Actions** in order to push images to ECR and perform deployment actions
- **1 instance profile / IAM role for the backend EC2 instances** in order to support ECR image pulls


### Instance Access Notes:
The project will use:
- **SSH**
- **EC2 key pairs**

for direct access to the backend EC2 instances.

SSM will not be used in this architecture.

This directly affects the security group design:
- the backend instances must allow inbound **SSH (port 22)** only from the approved administrator IP
- the DB instance will not allow direct inbound SSH access from outside

This decision also affects IAM design:
- no SSM-specific instance access configuration is required

### Backend Instance IAM Notes:
The backend EC2 instances will use an instance profile / IAM role in the current architecture.

This decision is based on the following:
- the backend containers will pull their images from Amazon ECR
- the backend deployment flow depends on AWS-managed container image access

The backend instance IAM role is required only for the AWS access that supports this deployment design.


### Repository Notes:
The project will use:
- **one Git repository**

All source code, infrastructure code, deployment logic, and automation scripts will be stored in the same repository.

### Architecture Flow:
**Client -> ALB -> Backend EC2 Targets -> Backend Containers -> MongoDB Container on dedicated DB EC2 instance**

Left to deside:
- Work tree files platform.
- Proiority list of what its important to implement first in this project, and what can wait for later. 
- Deside which version of each element or resources or library or extention in our project, So conflicts will not be exists. 