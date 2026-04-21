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

### Architecture Flow:
**Client -> ALB -> AWS Linux Host -> Backend Container -> MongoDB Container**

Left to deside:
- How many repos.
- Work tree files platform.