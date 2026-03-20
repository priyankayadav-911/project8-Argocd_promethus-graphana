<img width="1415" height="654" alt="diagram-export-9-23-2025-7_59_46-PM" src="https://github.com/user-attachments/assets/154f0e66-8923-41f8-9c04-3d73d24c4341" />

<img width="1428" height="656" alt="diagram-export-9-23-2025-8_05_49-PM" src="https://github.com/user-attachments/assets/d52d2dc6-914b-4d18-b903-77f6714362af" />


---

# DevOps CI/CD Pipeline on AWS with Terraform and Kubernetes


This project implements a CI/CD pipeline for a Node.js application, deployed on AWS infrastructure using Terraform-provisioned EC2 instances and a manually created Kubernetes cluster. The pipeline automates code scanning, building, containerization, and deployment, with monitoring via Prometheus and Grafana. ArgoCD enables GitOps-based deployments to Kubernetes. This `README.md` provides a comprehensive guide to the architecture, workflow, tools, and setup instructions.

## Infrastructure

The infrastructure is hosted on AWS, with EC2 instances provisioned via Terraform and a Kubernetes cluster created manually. Below is a detailed breakdown of components:

### EC2 Instance 1 (t2.large)
- **Purpose**: Hosts CI/CD and build tools.
- **Tools Installed**:
  - **Jenkins**: CI/CD server for pipeline orchestration (port 8080).
  - **Docker**: Builds and manages container images.
  - **SonarQube**: Performs static code analysis for quality and security (port 9000).
  - **Trivy**: Scans Docker images for vulnerabilities.
  - **NPM**: Builds Node.js applications.
- **Terraform Configuration**:
  - Instance type: `t2.large` (2 vCPUs, 8 GB RAM).
  - AMI: Latest Amazon Linux 2 or Ubuntu 20.04.
  - Security groups: Allow inbound traffic on ports 8080 (Jenkins), 9000 (SonarQube), and 22 (SSH).
  - IAM role: Grants access to AWS ECR for pushing/pulling images.
  - User data script: Installs Jenkins, Docker, SonarQube, Trivy, and Node.js/NPM during instance bootstrap.

### EC2 Instance 2 (t2.xlarge)
- **Purpose**: Hosts monitoring tools.
- **Tools Installed**:
  - **Prometheus**: Collects metrics from Kubernetes and the application (port 9090).
  - **Grafana**: Visualizes metrics via dashboards (port 3000).
- **Terraform Configuration**:
  - Instance type: `t2.xlarge` (4 vCPUs, 16 GB RAM) for better performance with monitoring workloads.
  - AMI: Same as EC2 Instance 1.
  - Security groups: Allow inbound traffic on ports 9090 (Prometheus), 80 (Grafana), and 22 (SSH).
  - User data script: Installs Helm, then deploys Prometheus and Grafana via Helm charts.
- **Helm Charts**:

 **Helm Installation:**
``` 
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 
sudo chmod 700 get_helm.sh 
sudo ./get_helm.sh 
helm version --client
```
Add Helm Repositories 
```
helm repo add stable https://charts.helm.sh/stable 
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 
helm search repo prometheus-community
```
### Kubernetes Cluster
- **Setup**: Manually created using AWS CLI (e.g., via `eksctl create cluster` or EKS API).
- **Configuration**:
  - Minimum 3 worker nodes (e.g., `t3.medium`) for high availability.
  - VPC and subnets configured to allow communication with EC2 instances.
  - ArgoCD installed in the cluster for GitOps deployments (`kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`).
  - Configured to pull images from AWS ECR using an IAM role for the Kubernetes nodes.
- **Networking**: Security groups allow Kubernetes API access and communication with Prometheus for metrics scraping.

 **Install and Configure Prometheus and Grafana:**

```kubectl create namespace prometheus ```

```helm install stable prometheus-community/kube-prometheus-stack -n prometheus ```

```kubectl get pods -n prometheus ```
```kubectl get svc -n prometheus ```

```kubectl patch svc stable-kube-prometheus-sta-prometheus -n prometheus -p '{"spec": {"type": "LoadBalancer"}}' ```
```kubectl patch svc stable-grafana -n prometheus -p '{"spec": {"type": "LoadBalancer"}}' ```

```kubectl get secret --namespace prometheus stable-grafana -o jsonpath="{.data.admin-password}" | base64 --decode ; echo``` 

```kubectl get svc -n prometheus ```


### AWS ECR
- **Purpose**: Private Docker registry for storing application images.
- **Setup**: Created via Terraform or AWS CLI (`aws ecr create-repository --repository-name nodejs`).

### GitHub Repository
- **Purpose**: Stores source code, Dockerfiles, and Kubernetes manifests (`deployment.yaml`, `service.yaml`).
- **Access**: Jenkins authenticates via SSH or GitHub API token.

### Terraform Setup
  ```
  terraform/
  ├── main.tf

  ```
- **Apply**: Run `terraform init`, `terraform plan`, and `terraform apply` to provision resources.

## CI/CD Workflow

The CI/CD pipeline automates building, testing, and deploying a Node.js application using Jenkins as the orchestrator. The pipeline is defined in a `Jenkinsfile` (declarative pipeline) in the GitHub repository.

### Pipeline Stages

1. **Clone Code**:
   - Jenkins clones the repository using Git credentials.
2. **Code Quality Scan**:
   - SonarQube scans the code for bugs, vulnerabilities, and code smells.
   - Configured via `sonar-project.properties` in the repo.
   - Fails if quality gates (e.g., coverage < 80%) are not met.
3. **Build Application**:
   - NPM installs dependencies (`npm install`) and builds the app (`npm run build`).
   - Artifacts are stored temporarily for Docker.
4. **Security Scan (Optional)**:
   - Trivy scans the Docker image for vulnerabilities (`trivy image myapp:latest`).
   - Configured to fail on critical or high-severity vulnerabilities.
5. **Build and Push Docker Image**:
   - Docker builds the image (`docker build -t myapp:$BUILD_NUMBER .`).
   - Tags and pushes to ECR (`docker push <aws-account-id>.dkr.ecr.<region>.amazonaws.com/myapp:$BUILD_NUMBER`).
   - Requires AWS CLI and ECR login (`aws ecr get-login-password`).
6. **Update Manifest**:
   - A script updates `deployment.yaml` in GitHub to reference the new image tag.
   - Example script:
     ```bash
     sed -i "s|image: .*|image: <aws-account-id>.dkr.ecr.<region>.amazonaws.com/myapp:$BUILD_NUMBER|" deployment.yaml
     git commit -m "Update image tag to $BUILD_NUMBER"
     git push origin main
     ```
7. **ArgoCD Sync**:
   - ArgoCD detects the manifest change and syncs the Kubernetes deployment.

### Jenkinsfile Example
```groovy
pipeline {
    agent any

    stages {
    stage('Checkout Code') {
        steps {
            echo 'scm git'
            git branch: 'main', url: 'https://github.com/adarsh0331/Project_7.git'
        }
    }
    

    stage('SonarQube Analysis') {
        steps {
            withSonarQubeEnv('SonarQube') {   // Jenkins -> Manage Jenkins -> Configure System -> SonarQube servers
                 script {
                   def scannerHome = tool 'SonarScannerCLI'   // Jenkins -> Manage Jenkins -> Tools -> SonarQube Scanner installations
                      sh """
                          ${scannerHome}/bin/sonar-scanner \
                          -Dsonar.projectKey=my-devops-app \
                          -Dsonar.sources=. \
                          -Dsonar.host.url=http://54.167.98.78:9000/ \
                          -Dsonar.login=squ_1d768aa35185eaddb20ecdfbe32f0740c673b5f6
                       """
                    }
                }
            }
        }

    stage('Building the code') {
      steps {
        sh 'ls -ltr'
        // build the project and create a JAR file
        sh 'npm install'
      }
    }

    stage('Build docker image'){
    steps{
        script{
            echo 'docker image build'
        sh 'sudo docker build -t adarshbarkunta/nodejs:${BUILD_NUMBER} .'
        }
    }
}
		
     stage('docker image scan'){
     steps{
         sh "sudo trivy image adarshbarkunta/nodejs:${BUILD_NUMBER}"
     }
 }		


stage('Push image to ECR') {
    steps {
        withAWS(credentials: 'aws-creds', region: 'us-east-1') {
            script {
                sh '''
                  aws ecr get-login-password --region us-east-1 \
                  | sudo docker login --username AWS --password-stdin 526344317172.dkr.ecr.us-east-1.amazonaws.com
                  
                  sudo docker tag adarshbarkunta/nodejs:${BUILD_NUMBER} 526344317172.dkr.ecr.us-east-1.amazonaws.com/nodejs:${BUILD_NUMBER}
                  sudo docker push 526344317172.dkr.ecr.us-east-1.amazonaws.com/nodejs:${BUILD_NUMBER}
                '''
            }
        }
    }
}
       stage('Update Deployment File') {
		
		 environment {
            GIT_REPO_NAME = "Project_7"
            GIT_USER_NAME = "adarsh0331"
        }
		
            steps {
                echo 'Update Deployment File'
				withCredentials([string(credentialsId: 'githubtoken', variable: 'githubtoken')]) 
				{
                  sh '''
                    git config user.email "adarsh@gmail.com"
                    git config user.name "adarsh"
                    BUILD_NUMBER=${BUILD_NUMBER}
					sed -i "s|image: .*|image: 526344317172.dkr.ecr.us-east-1.amazonaws.com/nodejs:$BUILD_NUMBER|" deploymentfiles/deployment.yml
                    git add .
                    
                    git commit -m "Update deployment image to version ${BUILD_NUMBER}"

                    git push https://${githubtoken}@github.com/${GIT_USER_NAME}/${GIT_REPO_NAME} HEAD:main
                '''
				  
                 }
				
            }
        }

  }
}
```

## Monitoring

Monitoring ensures observability of the Kubernetes cluster and application.

### Components
- **Prometheus**:
  - Scrapes metrics from Kubernetes pods, nodes, and the application (if instrumented with `/metrics` endpoint).
  - Configured with scrape jobs in `prometheus.yml`:
    ```yaml
    scrape_configs:
      - job_name: 'kubernetes'
        kubernetes_sd_configs:
        - role: pod
          namespaces:
            names: [default, argocd]
      - job_name: 'application'
        static_configs:
        - targets: ['<app-service>:8080']
    ```
  - Installed via Helm: `helm install prometheus prometheus-community/prometheus`.
- **Grafana**:
  - Connects to Prometheus as a data source.
  - Dashboards display CPU/memory usage, pod health, deployment status, and custom app metrics.
  - Installed via Helm: `helm install grafana grafana/grafana`.
  - Access: `http://<ec2-ip>:3000`, default login (admin/admin).

### Monitoring Flow
1. Kubernetes pods expose metrics (via kube-state-metrics, node-exporter, or app-specific endpoints).
2. Prometheus scrapes metrics at regular intervals.
3. Grafana queries Prometheus to visualize metrics in dashboards.
4. Alerts (optional): Configure in Prometheus with Alertmanager for notifications (e.g., Slack, email) on high CPU or failed deployments.

## Tools Used

| Tool         | Purpose                              | Version (Recommended) | Location              |
|--------------|--------------------------------------|-----------------------|-----------------------|
| Jenkins      | CI/CD pipeline orchestration         | 2.426.x (LTS)         | EC2 Instance 1        |
| SonarQube    | Code quality and security scanning   | 9.9.x (Community)     | EC2 Instance 1        |
| Docker       | Container image building            | 24.x                  | EC2 Instance 1        |
| Trivy        | Image vulnerability scanning         | 0.45.x                | EC2 Instance 1        |
| NPM          | Node.js app building                 | 10.x (with Node.js 20)| EC2 Instance 1        |
| ArgoCD       | GitOps-based Kubernetes deployments  | 2.8.x                 | Kubernetes Cluster    |
| Prometheus   | Metrics collection and alerting      | 2.47.x (via Helm)     | EC2 Instance 2        |
| Grafana      | Metrics visualization                | 10.x (via Helm)       | EC2 Instance 2        |
| GitHub       | Code and manifest storage           | N/A                   | External              |
| AWS ECR      | Docker image registry                | N/A                   | AWS                   |
| Kubernetes   | Container orchestration              | 1.28.x                | AWS (Manual Cluster)  |

All tools are open-source except AWS services. Use latest stable versions unless specified.

## Deployment Flow

The deployment process is GitOps-driven using ArgoCD:

1. **Image Push**: Jenkins builds and pushes the Docker image to AWS ECR.
3. **Manifest Update**: Jenkins updates `deployment.yaml` in GitHub with the new image tag.
   
   - Example `deployment.yaml`:

 ```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mc-app
  labels:
    app: mc-app
spec:
  replicas: 4
  selector:
    matchLabels:
      app: mc-app
  template:
    metadata:
      labels:
        app: mc-app
    spec:
      containers:
      - name: mc-app
        image: 526344317172.dkr.ecr.us-east-1.amazonaws.com/nodejs:16
        ports:
        - containerPort: 3000
```
3. **ArgoCD Sync**:
   - ArgoCD monitors the GitHub repo for changes.
   - Detects the updated `deployment.yaml` and triggers a sync.
   - Applies the manifest to Kubernetes using `kubectl apply`.
4. **Kubernetes Deployment**:
   - Kubernetes pulls the image from ECR 
   - Rolls out new pods with a rolling update strategy for zero downtime.
5. **Monitoring**:
   - Prometheus scrapes metrics from the new pods.
   - Grafana visualizes metrics in real-time.

### Rollback
- Revert the `deployment.yaml` commit in GitHub to the previous image tag.
- ArgoCD auto-syncs, rolling back the deployment.
- Alternatively, use `kubectl rollout undo deployment/myapp`.

## Setup Instructions

1. **Provision Infrastructure**:
   - Clone the Terraform repo: `git clone <terraform-repo>`.
   - Configure AWS credentials (`aws configure`).
   - Run `terraform init`, `terraform plan`, and `terraform apply`.
2. **Create Kubernetes Cluster**:
   - Use `eksctl create cluster --name my-cluster --region <region> --nodegroup-name workers --node-type t3.medium --nodes 3`.
   - Install ArgoCD: `kubectl create namespace argocd && kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`.
3. **Configure Jenkins**:
   - Access Jenkins at `http://<ec2-1-ip>:8080`.
   - Install plugins: Git, Pipeline, SonarQube Scanner, Docker, AWS Credentials.
   - Configure GitHub webhook and credentials.
   - Add SonarQube server in Jenkins global config.
4. **Set Up Monitoring**:
   - SSH into EC2 Instance 2 and install Helm.
   - Deploy Prometheus and Grafana via Helm commands (see Monitoring section).
   - Configure Grafana with Prometheus data source.
5. **Create GitHub Repository**:
   - Add source code, `Dockerfile`, `Jenkinsfile`, and Kubernetes manifests.
   - Configure webhook to point to Jenkins.
6. **Create ECR Repository**:
   - Run `aws ecr create-repository --repository-name myapp`.
   - Assign IAM roles to EC2 Instance 1 and Kubernetes nodes.
7. **Run Pipeline**:
   - Commit code to GitHub to trigger Jenkins.
   - Monitor pipeline in Jenkins UI, ArgoCD UI, and Grafana dashboards.

## Maintenance

- **Upgrades**: Regularly update tools (Jenkins, ArgoCD, etc.) to stable versions.
- **Backups**: Backup Jenkins home (`~/.jenkins`), SonarQube data, and Grafana dashboards.
- **Security**: Rotate AWS IAM credentials and GitHub tokens periodically.
- **Scaling**: Add more Kubernetes nodes or upgrade EC2 instances for higher workloads.
- **Logs**: Use Kubernetes logs (`kubectl logs`) and Grafana Loki (optional) for log aggregation.

## Troubleshooting

- **Jenkins Failure**: Check pipeline logs in Jenkins UI or `/var/lib/jenkins/logs`.
- **SonarQube Issues**: Verify quality gate settings and network access (port 9000).
- **Trivy Failures**: Adjust severity thresholds if scans are too strict.
- **ArgoCD Sync Issues**: Check ArgoCD UI for sync errors or GitHub connectivity.
- **Monitoring Gaps**: Ensure Prometheus scrape targets are correct and pods expose metrics.

---
