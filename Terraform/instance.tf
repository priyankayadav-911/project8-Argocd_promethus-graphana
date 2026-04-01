provider "aws" {
  region = "us-east-1"
}


# Security Group
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Allow SSH and HTTP"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "jenkins"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SonarQube"
    from_port   = 9000
    to_port     = 9000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

 ingress {
    description = "prometheus"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
 ingress {
    description = "app"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ----------------------------
# Instance 1: jenkins
# ----------------------------
resource "aws_instance" "Jenkins_server" {
  ami           = "ami-0c3389a4fa5bddaad" # Amazon Linux 2 (us-east-1)
  instance_type = "c7i-flex.large"
  key_name      = "manikey"
  security_groups = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y

              sudo yum install git -y
  
              # Install Docker

              echo ">>> Installing Docker..."
              sudo yum install -y docker
              sudo systemctl start docker
              sudo systemctl enable docker
              sudo usermod -aG docker $USER

              # Install Jenkins

              echo ">>> Installing Jenkins..."

              sudo yum update -y
              sudo wget -O /etc/yum.repos.d/jenkins.repo  https://pkg.jenkins.io/redhat-stable/jenkins.repo
              sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
              sudo yum upgrade
              sudo yum install java-21-amazon-corretto -y
              sudo yum install jenkins -y
              sudo systemctl enable jenkins
              sudo systemctl start jenkins


              # Install Trivy

              echo ">>> Installing Trivy..."
              curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sudo sh -s -- -b /usr/local/bin

              # Install SonarQube (with Docker)
 
              echo ">>> Installing SonarQube using Docker..."
              # Pull and run SonarQube container
              sudo docker run -d --name sonarqube \
              -p 9000:9000 \
              sonarqube:lts

              # Install Node.js + npm

              echo ">>> Installing Node.js & npm..."
              curl -sL https://rpm.nodesource.com/setup_18.x | sudo bash -
              sudo yum install -y nodejs


              # Final Info

              echo ">>> Installation Completed!"
              echo "Jenkins running on: http://<your-server-ip>:8080"
              echo "SonarQube running on: http://<your-server-ip>:9000"
              echo "Use 'sudo cat /var/lib/jenkins/secrets/initialAdminPassword' for Jenkins password."
              EOF

  tags = {
    Name = "jenkins-Server"
  }
}

# ----------------------------
# Instance 2: k8s Server
# ----------------------------
resource "aws_instance" "k8s_server" {
  ami           = "ami-0c3389a4fa5bddaad"
  instance_type = "c7i-flex.large"
  key_name      = "manikey"
  security_groups = [aws_security_group.ec2_sg.name]

  user_data = <<-EOF
              #!/bin/bash
              sudo yum update -y
              
              # Install dependencies

              echo ">>> Installing required packages..."
              sudo yum install -y curl wget git tar

              # Install kubectl

              echo ">>> Installing kubectl..."
              curl -LO "https://dl.k8s.io/release/$(curl -sSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x kubectl
              sudo mv kubectl /usr/local/bin/
              kubectl version --client
              curl -sSL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_Linux_amd64.tar.gz" -o eksctl.tar.gz
              tar -xzf eksctl.tar.gz
              sudo mv eksctl /usr/local/bin/
              eksctl version


              # Install Helm

              echo ">>> Installing Helm..."
              curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash


              # Add Helm Repos

              echo ">>> Adding Helm repositories..."
              helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
              helm repo add grafana https://grafana.github.io/helm-charts
              helm repo add argo https://argoproj.github.io/argo-helm
              helm repo update

              EOF

  tags = {
    Name = "k8s-Server"
  }
}
