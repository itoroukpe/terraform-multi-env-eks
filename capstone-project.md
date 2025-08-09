 # Capstone Project - Devops Engineering Students - Rondus LLC 

---

# 1) Project overview

**Goal:** Build a scientific calculator web app (Java + HTML/CSS), package it with Docker, scan & store artifacts (SonarQube + Nexus), ship images to ECR, and deploy to **Amazon EKS** via a **Jenkins** CI/CD pipeline. Infra is provisioned with **Terraform**.

**Stacks**

* **Code:** Java (Spring Boot), HTML/CSS
* **Build:** Maven
* **CI/CD:** Jenkins (pipeline), GitHub (PRs & webhooks)
* **Quality:** SonarQube
* **Artifacts:** Nexus Repository (Maven releases/snapshots)
* **Containers:** Docker, ECR
* **Orchestration:** Kubernetes (EKS)
* **Infra:** Terraform (VPC + EKS + one EC2 “tools” host running Jenkins/SonarQube/Nexus via Docker Compose)

---

# 2) Repo layout

```
devops-capstone/
├─ app/
│  ├─ pom.xml
│  ├─ src/main/java/com/example/calc/CalcApplication.java
│  ├─ src/main/java/com/example/calc/CalcController.java
│  ├─ src/main/resources/static/index.html
│  ├─ src/main/resources/static/styles.css
│  └─ Dockerfile
├─ k8s/
│  ├─ deployment.yaml
│  ├─ service.yaml
│  └─ ingress.yaml
├─ Jenkinsfile
├─ sonar-project.properties
├─ infra/
│  ├─ tools/               # EC2 host for Jenkins/Sonar/Nexus (via docker-compose)
│  │  ├─ main.tf
│  │  └─ docker-compose.yml
│  └─ eks/                 # VPC + EKS
│     ├─ main.tf
│     ├─ variables.tf
│     └─ outputs.tf
└─ README.md
```

---

# 3) App code (Java + HTML/CSS)

## `app/pom.xml`

```xml
<project xmlns="http://maven.apache.org/POM/4.0.0"  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="http://maven.apache.org/POM/4.0.0  http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.example</groupId><artifactId>calc</artifactId><version>1.0.0</version>
  <properties>
    <java.version>17</java.version>
    <spring.boot.version>3.2.5</spring.boot.version>
  </properties>
  <dependencies>
    <dependency>
      <groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-web</artifactId>
      <version>${spring.boot.version}</version>
    </dependency>
    <dependency>
      <groupId>org.springframework.boot</groupId><artifactId>spring-boot-starter-test</artifactId>
      <version>${spring.boot.version}</version><scope>test</scope>
    </dependency>
  </dependencies>
  <build>
    <plugins>
      <plugin>
        <groupId>org.springframework.boot</groupId><artifactId>spring-boot-maven-plugin</artifactId>
        <version>${spring.boot.version}</version>
      </plugin>
    </plugins>
  </build>
</project>
```

## `app/src/main/java/com/example/calc/CalcApplication.java`

```java
package com.example.calc;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
public class CalcApplication {
  public static void main(String[] args) { SpringApplication.run(CalcApplication.class, args); }
}
```

## `app/src/main/java/com/example/calc/CalcController.java`

```java
package com.example.calc;
import org.springframework.web.bind.annotation.*;
import java.util.Map;

@RestController
public class CalcController {

  @GetMapping("/api/ping")
  public Map<String,String> ping() { return Map.of("status","ok"); }

  @GetMapping("/api/calc")
  public Map<String, Object> calc(
    @RequestParam String op,
    @RequestParam double a,
    @RequestParam(required=false) Double b
  ) {
    double result;
    switch (op.toLowerCase()) {
      case "add": result = a + (b==null?0:b); break;
      case "sub": result = a - (b==null?0:b); break;
      case "mul": result = a * (b==null?1:b); break;
      case "div": result = (b==null?1:b)==0 ? Double.NaN : (a / b); break;
      case "sin": result = Math.sin(a); break;
      case "cos": result = Math.cos(a); break;
      case "tan": result = Math.tan(a); break;
      case "pow": result = Math.pow(a, b==null?1:b); break;
      default: throw new IllegalArgumentException("Unsupported op: "+op);
    }
    return Map.of("op", op, "a", a, "b", b, "result", result);
  }
}
```

## `app/src/main/resources/static/index.html`

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8" />
  <title>Scientific Calculator</title>
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <h1>Scientific Calculator</h1>
  <form id="calc">
    <label>Operation
      <select name="op">
        <option>add</option><option>sub</option><option>mul</option><option>div</option>
        <option>sin</option><option>cos</option><option>tan</option><option>pow</option>
      </select>
    </label>
    <label>A <input name="a" type="number" step="any" required></label>
    <label>B <input name="b" type="number" step="any" placeholder="optional"></label>
    <button>Compute</button>
  </form>
  <pre id="out"></pre>
  <script>
    const f = document.getElementById('calc'); const out = document.getElementById('out');
    f.addEventListener('submit', async (e) => {
      e.preventDefault();
      const q = new URLSearchParams(new FormData(f)).toString();
      const r = await fetch('/api/calc?'+q); out.textContent = JSON.stringify(await r.json(), null, 2);
    });
  </script>
</body>
</html>
```

## `app/src/main/resources/static/styles.css`

```css
body { font-family: system-ui, Arial, sans-serif; margin: 2rem; }
h1 { margin-bottom: 1rem; }
form { display: grid; gap: .8rem; max-width: 320px; }
label { display: grid; gap: .3rem; font-size: 14px; }
button { padding: .5rem .8rem; cursor: pointer; }
pre { background: #111; color: #0f0; padding: 1rem; margin-top: 1rem; }
```

---

# 4) Dockerfile (multi-stage)

## `app/Dockerfile`

```dockerfile
# --- Build stage ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn -q -e -B -DskipTests dependency:go-offline
COPY src ./src
RUN mvn -q -e -B package -DskipTests

# --- Runtime stage ---
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/*.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-jar","/app/app.jar"]
```

---

# 5) Kubernetes manifests

## `k8s/deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: calc-app
  labels: { app: calc }
spec:
  replicas: 2
  selector: { matchLabels: { app: calc } }
  template:
    metadata: { labels: { app: calc } }
    spec:
      containers:
        - name: calc
          image: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/calc:{{GIT_COMMIT}}
          ports: [{ containerPort: 8080 }]
          readinessProbe:
            httpGet: { path: /api/ping, port: 8080 }
            initialDelaySeconds: 5
          livenessProbe:
            httpGet: { path: /api/ping, port: 8080 }
            initialDelaySeconds: 10
```

## `k8s/service.yaml`

```yaml
apiVersion: v1
kind: Service
metadata:
  name: calc-svc
spec:
  selector: { app: calc }
  ports:
    - port: 80
      targetPort: 8080
  type: ClusterIP
```

## `k8s/ingress.yaml` *(optional; requires an Ingress controller)*

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: calc-ing
  annotations:
    kubernetes.io/ingress.class: alb
spec:
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: calc-svc, port: { number: 80 } } }
```

---

# 6) SonarQube config

## `sonar-project.properties`

```properties
sonar.projectKey=calc
sonar.projectName=calc
sonar.sourceEncoding=UTF-8
sonar.sources=src/main/java
sonar.tests=src/test/java
sonar.java.binaries=target
```

---

# 7) Jenkins pipeline

## `Jenkinsfile`

```groovy
pipeline {
  agent any
  environment {
    APP_NAME       = "calc"
    AWS_REGION     = "us-west-2"
    ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    ECR_REPO       = "${ECR_REGISTRY}/${APP_NAME}"
    IMAGE_TAG      = "${env.GIT_COMMIT}"
    SONAR_URL      = "http://localhost:9000"
    SONAR_TOKEN    = credentials('sonar-token')
    MAVEN_OPTS     = "-Dmaven.test.skip=false"
    NEXUS_URL      = "http://localhost:8081"
  }
  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Build & Unit Test (Maven)') {
      steps {
        sh 'cd app && mvn -B -e -U clean package'
      }
      post { success { junit 'app/target/surefire-reports/*.xml' } }
    }

    stage('SonarQube Analysis') {
      steps {
        withSonarQubeEnv('SonarQube') {
          sh """
            cd app
            sonar-scanner \
              -Dsonar.host.url=${SONAR_URL} \
              -Dsonar.login=${SONAR_TOKEN} \
              -Dproject.settings=../sonar-project.properties
          """
        }
      }
    }

    stage('Publish JAR to Nexus') {
      steps {
        sh 'cd app && mvn -B -e deploy -DskipTests -Dnexus.url=$NEXUS_URL'
      }
    }

    stage('Docker Build & Push to ECR') {
      steps {
        sh """
          aws ecr get-login-password --region ${AWS_REGION} \
            | docker login --username AWS --password-stdin ${ECR_REGISTRY} || true
          aws ecr describe-repositories --repository-names ${APP_NAME} \
            --region ${AWS_REGION} || \
          aws ecr create-repository --repository-name ${APP_NAME} --region ${AWS_REGION}
          cd app
          docker build -t ${ECR_REPO}:${IMAGE_TAG} .
          docker push ${ECR_REPO}:${IMAGE_TAG}
        """
      }
    }

    stage('Deploy to EKS') {
      steps {
        sh """
          aws eks --region ${AWS_REGION} update-kubeconfig --name ${APP_NAME}-eks
          sed "s#<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/calc:{{GIT_COMMIT}}#${ECR_REPO}:${IMAGE_TAG}#g" k8s/deployment.yaml | kubectl apply -f -
          kubectl apply -f k8s/service.yaml
          # Ingress optional:
          # kubectl apply -f k8s/ingress.yaml
          kubectl rollout status deploy/calc-app
        """
      }
    }
  }
}
```

> Configure Jenkins creds: `AWS_ACCOUNT_ID`, `sonar-token` (secret text), and install: Docker, AWS CLI, kubectl, JDK 17, Maven, Sonar Scanner plugin, Pipeline, Git.

---

# 8) “Tools” host (Jenkins, SonarQube, Nexus) infra

## `infra/tools/main.tf` (simplified; uses latest providers & no S3 backend)

```hcl
terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0.0" }
  }
}
provider "aws" { region = "us-west-2" }

resource "aws_key_pair" "tools" {
  key_name   = "tools-key"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "tools_sg" {
  name        = "tools-sg"
  description = "Allow SSH, HTTP, HTTPS"
  vpc_id      = data.aws_vpc.default.id

  ingress { from_port=22  to_port=22  protocol="tcp" cidr_blocks=["0.0.0.0/0"] }
  ingress { from_port=80  to_port=80  protocol="tcp" cidr_blocks=["0.0.0.0/0"] }
  ingress { from_port=443 to_port=443 protocol="tcp" cidr_blocks=["0.0.0.0/0"] }
  ingress { from_port=8080 to_port=8081 protocol="tcp" cidr_blocks=["0.0.0.0/0"] } # Jenkins/Nexus
  ingress { from_port=9000 to_port=9000 protocol="tcp" cidr_blocks=["0.0.0.0/0"] } # SonarQube
  egress  { from_port=0 to_port=0 protocol="-1" cidr_blocks=["0.0.0.0/0"] }
}

data "aws_vpc" "default" { default = true }
data "aws_subnet_ids" "default" { vpc_id = data.aws_vpc.default.id }

resource "aws_instance" "tools" {
  ami           = data.aws_ami.amzn2.id
  instance_type = "t3.large"
  subnet_id     = element(data.aws_subnet_ids.default.ids, 0)
  key_name      = aws_key_pair.tools.key_name
  vpc_security_group_ids = [aws_security_group.tools_sg.id]
  user_data = <<'EOF'
#!/bin/bash
set -e
yum update -y
amazon-linux-extras install docker -y
systemctl enable --now docker
usermod -aG docker ec2-user
curl -L "https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
mkdir -p /opt/tools
cat >/opt/tools/docker-compose.yml <<YML
version: "3.8"
services:
  jenkins:
    image: jenkins/jenkins:lts
    ports: ["8080:8080","50000:50000"]
    volumes: ["jenkins_home:/var/jenkins_home","/var/run/docker.sock:/var/run/docker.sock"]
  sonarqube:
    image: sonarqube:lts-community
    ports: ["9000:9000"]
    environment:
      - SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true
  nexus:
    image: sonatype/nexus3:latest
    ports: ["8081:8081"]
    volumes: ["nexus-data:/nexus-data"]
volumes: { jenkins_home: {}, nexus-data: {} }
YML
cd /opt/tools && /usr/local/bin/docker-compose up -d
EOF
  tags = { Name = "tools-host" }
}

data "aws_ami" "amzn2" {
  owners      = ["amazon"]
  most_recent = true
  filter { name="name" values=["amzn2-ami-hvm-*-x86_64-gp2"] }
}

output "tools_public_ip" { value = aws_instance.tools.public_ip }
```

## `infra/tools/docker-compose.yml` (already baked into user\_data—kept here for reference)

```yaml
version: "3.8"
services:
  jenkins:
    image: jenkins/jenkins:lts
    ports: ["8080:8080","50000:50000"]
    volumes: ["jenkins_home:/var/jenkins_home","/var/run/docker.sock:/var/run/docker.sock"]
  sonarqube:
    image: sonarqube:lts-community
    ports: ["9000:9000"]
    environment: [ "SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true" ]
  nexus:
    image: sonatype/nexus3:latest
    ports: ["8081:8081"]
    volumes: ["nexus-data:/nexus-data"]
volumes: { jenkins_home: {}, nexus-data: {} }
```

---

# 9) EKS (VPC + Cluster) with Terraform (no S3 backend)

## `infra/eks/main.tf`

```hcl
terraform {
  required_version = ">= 1.4.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = ">= 2.25.0" }
  }
}

provider "aws" { region = var.region }

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"
  name = "${var.name}-vpc"
  cidr = "10.50.0.0/16"
  azs  = ["${var.region}a","${var.region}b"]
  public_subnets  = ["10.50.1.0/24","10.50.2.0/24"]
  private_subnets = ["10.50.11.0/24","10.50.12.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Environment = var.name }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.4.0"

  cluster_name    = "${var.name}-eks"
  cluster_version = "1.28"
  subnet_ids      = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id
  enable_irsa     = true

  eks_managed_node_groups = {
    default = {
      desired_size   = 2
      max_size       = 3
      min_size       = 1
      instance_types = ["t3.medium"]
    }
  }

  tags = { Environment = var.name }
}

output "cluster_name"     { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "vpc_id"           { value = module.vpc.vpc_id }
```

## `infra/eks/variables.tf`

```hcl
variable "region" { type = string; default = "us-west-2" }
variable "name"   { type = string; default = "calc" }
```

## `infra/eks/outputs.tf`

```hcl
output "private_subnets" { value = module.vpc.private_subnets }
```

**Apply**

```bash
cd infra/eks
terraform init -upgrade
terraform apply -auto-approve
aws eks --region us-west-2 update-kubeconfig --name calc-eks
```

---

# 10) CI/CD glue steps (what students configure)

1. **GitHub repo** with webhook to Jenkins (`/github-webhook/`).
2. On **tools host**, visit:

   * Jenkins: `http://<tools_ip>:8080`
   * SonarQube: `http://<tools_ip>:9000` (create project + token)
   * Nexus: `http://<tools_ip>:8081` (create Maven hosted repos or use defaults)
3. Jenkins global tools: JDK 17, Maven, SonarScanner, Docker, kubectl, AWS CLI.
4. Jenkins credentials:

   * `AWS access key/secret` (for ECR + EKS)
   * `sonar-token` (Secret text)
   * optionally GitHub credentials if needed
5. Create ECR permissions on IAM user/role used by Jenkins.

---

# 11) Student success checklist

* [ ] `terraform apply` in `infra/tools` → get public IP; Jenkins/Sonar/Nexus reachable
* [ ] `terraform apply` in `infra/eks` → get EKS cluster; `kubectl get nodes` works
* [ ] Jenkins pipeline runs on PR/merge:

  * Maven build & tests pass
  * Sonar analysis reports quality
  * JAR published to Nexus
  * Docker image built & pushed to ECR
  * K8s deployment updated in EKS and rolls out
* [ ] App reachable via Service/Ingress (ALB if you enable ingress)

