This file will define the architecture of the GreenCart project.
To change decisions from this file, you must obtain explicit permission.

## Selected Technology Stack

- **Backend:** Node.js with TypeScript and Express
- **Frontend:** HTML and plain JavaScript (`app.js`)
- **Database:** MongoDB
- **Infrastructure as Code:** Terraform
- **Cloud Platform:** AWS
- **Deployment Model:** Container-based architecture
- **Load Balancer:** AWS Application Load Balancer (ALB)
- **CI/CD:** GitHub Actions + Amazon ECR + Docker Compose-based automated deployment to AWS Linux host

### Backend Notes:
Express is used as the backend web framework in order to:
- define API routes
- handle HTTP requests and responses
- serve static frontend files when required

### Frontend Notes:
The frontend is intentionally kept simple.
It uses plain HTML and JavaScript without a frontend framework and without TypeScript.

### Load Balancer Notes:
The project includes an **AWS Application Load Balancer (ALB)** as part of the bonus architecture scope.

The ALB is responsible for:
- acting as the public entry point of the application
- routing incoming HTTP/HTTPS traffic to the backend service

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

### IAM Notes:
The project will use:
- **1 GitHub OIDC provider** connected to AWS
- **1 IAM role for GitHub Actions** in order to push images to ECR and perform deployment actions
- **1 instance profile / IAM role for the backend EC2 instances** in order to support ECR image pulls

### Architecture Flow:
**Client -> ALB -> Backend EC2 Targets -> Backend Containers -> MongoDB Container on dedicated DB EC2 instance**

Left to deside:
- How many repos.
- Work tree files platform.
- Proiority list of what its important to implement first in this project, and what can wait for later. 
- Deside which version of each element or resources or library or extention in our project, So conflicts will not be exists. 