# Hello World on Amazon EKS

Production-style deployment of a containerized Flask service on Amazon EKS, with infrastructure defined in Terraform and two independent continuous delivery pipelines.

![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?logo=terraform&logoColor=white)
![AWS EKS](https://img.shields.io/badge/AWS-EKS%201.31-FF9900?logo=amazonaws&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?logo=docker&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-v3-0F1689?logo=helm&logoColor=white)
![Jenkins](https://img.shields.io/badge/Jenkins-D24939?logo=jenkins&logoColor=white)
![Argo CD](https://img.shields.io/badge/Argo%20CD-EF7B4D?logo=argo&logoColor=white)

---

## Overview

A Flask application is packaged as a Docker image, stored in Amazon ECR, and deployed to an EKS cluster as a Helm release. The cluster, its network, and its IAM roles are provisioned entirely by Terraform. Traffic is served through an Application Load Balancer created from a Kubernetes Ingress. The workload scales on two independent axes — pods by the Horizontal Pod Autoscaler, nodes by the Cluster Autoscaler.

Two delivery pipelines are implemented on separate branches:

| Branch | Model | Toolchain |
|---|---|---|
| `main` | Push-based | Jenkins → ECR → `kubectl` + Helm |
| `gitops` | Pull-based | GitHub Actions → ECR → Argo CD |

No long-lived AWS access keys exist anywhere in the project. All three compute contexts authenticate with short-lived credentials: an EC2 instance profile for the build server, IRSA for in-cluster controllers, and OIDC federation for GitHub Actions.

**Deployed endpoint:** `http://k8s-default-hello-2fe244ada8-578129713.us-east-1.elb.amazonaws.com`

---

## Architecture

```
                          Internet
                             │
                  ┌──────────▼───────────┐
                  │  Application Load    │   created by the AWS Load Balancer
                  │  Balancer            │   Controller from an Ingress object
                  └──────────┬───────────┘
                             │
                  ┌──────────▼───────────┐
                  │  Service (ClusterIP) │
                  └──────────┬───────────┘
                             │
                  ┌──────────▼───────────┐
                  │  Pods — Gunicorn     │
                  │  :5001               │
                  └──────────┬───────────┘
                             │
                  ┌──────────▼───────────┐
                  │  EKS managed node    │
                  │  group — t3.small    │
                  │  min 1 / max 4       │
                  └──────────────────────┘
```

**Scaling layers**

```
Horizontal Pod Autoscaler  →  pods    1 → 12   at 50% CPU or 50% memory
Cluster Autoscaler         →  nodes   1 → 4    when pods cannot be scheduled
```

**Delivery paths**

```
  main branch                          gitops branch
  ───────────                          ─────────────
  git push                             git push
      │  webhook                           │
      ▼                                    ▼
  Jenkins (EC2)                        GitHub Actions
      │                                    │
      ▼                                    ▼
  build → ECR                          build → ECR
      │                                    │
      ▼                                    ▼
  helm upgrade --install               commit image tag to values.yaml
      │                                    │
      ▼                                    ▼
  cluster                              Argo CD syncs cluster
     (PUSH)                                (PULL)
```

---

## Repository structure

```
.
├── app/                        Flask application
│   ├── app.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── .dockerignore
│
├── terraform/                  Infrastructure as code
│   ├── 1-auth.tf               Provider and region
│   ├── 2-network.tf            VPC, subnets, IGW, NAT, routing
│   ├── 3-ecr.tf                Container registry and lifecycle policy
│   ├── 4-Iam.tf                Roles for EKS, nodes and the build server
│   ├── 5-eks.tf                Cluster, node group, access entries
│   ├── 6-sg.tf                 Security groups and rules
│   ├── 7-jenkins.tf            Build server and control node
│   ├── 8-variables.tf
│   ├── 9-outputs.tf
│   ├── 10-s3_backend.tf        Remote state
│   ├── 11-irsa.tf              OIDC provider and in-cluster service roles
│   └── 12-github-oidc.tf       GitHub Actions federation
│
├── helm/hello-world/           Application chart
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       └── hpa.yaml
│
├── scripts/
│   └── verify-connectivity.sh  Build server pre-flight check
│
├── argocd/application.yaml     gitops branch
├── .github/workflows/build.yml gitops branch
├── Jenkinsfile                 main branch
├── playbook.yaml               Build server configuration
└── inventory.ini
```

---

## Prerequisites

| Requirement | Version / notes |
|---|---|
| AWS CLI | v2, with permissions for IAM, VPC, EKS and EC2 |
| Terraform | ≥ 1.5 |
| kubectl | matching the cluster minor version (1.31) |
| Helm | v3 |
| Docker | Docker Desktop or equivalent |
| EC2 key pair | for access to the build server |
| GitHub personal access token | classic, `repo` scope |

---

## Getting started

### 1. Configure

```bash
git clone https://github.com/FaboCloudsurf/Tech_challenge_2.git
cd Tech_challenge_2
```

Create `terraform/terraform.tfvars`:

```hcl
project_name          = "tech_challenge_2"
environment           = "production"
aws_region            = "us-east-1"
key_name              = "<ec2-key-pair-name>"
my_ip_cidr            = "<your.public.ip>/32"
jenkins_instance_type = "t3.medium"
node_instance_type    = "t3.small"
cluster_version       = "1.31"
```

This file is gitignored — it holds environment-specific values.

### 2. Fetch the load balancer controller IAM policy

```bash
cd terraform
curl -o alb-iam-policy.json \
  https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json
```

> Pull this from `main` rather than a release tag. Newer controller builds call API actions that older policy documents do not grant, and the resulting denial surfaces only when an Ingress is created.

### 3. Provision

```bash
terraform init
terraform plan
terraform apply
```

Approximately 35 resources; roughly 15 minutes, most of it EKS control plane provisioning.

### 4. Connect

```bash
aws eks update-kubeconfig --region us-east-1 --name tech_challenge_2_eks
kubectl get nodes
```

### 5. Install cluster add-ons

```bash
# Metrics pipeline — the HPA cannot function without it
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm upgrade --install metrics-server metrics-server/metrics-server \
  --namespace kube-system

# Provisions ALBs from Ingress objects
helm repo add eks https://aws.github.io/eks-charts
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=tech_challenge_2_eks \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform -chdir=terraform output -raw alb_controller_role_arn) \
  --set region=us-east-1 \
  --set vpcId=$(terraform -chdir=terraform output -raw vpc_id)

# Node-level scaling — image tag must match the cluster minor version
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=tech_challenge_2_eks \
  --set awsRegion=us-east-1 \
  --set image.tag=v1.31.0 \
  --set rbac.serviceAccount.create=true \
  --set rbac.serviceAccount.name=cluster-autoscaler \
  --set rbac.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(terraform -chdir=terraform output -raw cluster_autoscaler_role_arn)
```

`--set region` and `--set vpcId` are required. The controller's pods reach the instance metadata service through an additional network hop and time out attempting VPC discovery without them.

**Verify the add-ons are functioning, not merely running:**

```bash
kubectl top nodes
kubectl logs -n kube-system deploy/cluster-autoscaler-aws-cluster-autoscaler | grep "Registering ASG"
kubectl -n kube-system get configmap cluster-autoscaler-status -o yaml | head -12
```

`Registering ASG …` confirms tag-based node group discovery. `autoscalerStatus: Running` confirms initialization completed. A Cluster Autoscaler blocked during startup still reports `1/1 Running`.

---

## Deployment

### Manual

```bash
export ECR_REPO=730335577638.dkr.ecr.us-east-1.amazonaws.com/tech_challenge_2-ecr-app

aws ecr get-login-password --region us-east-1 \
  | docker login --username AWS --password-stdin $ECR_REPO

docker build --platform linux/amd64 -t $ECR_REPO:latest ./app
docker push $ECR_REPO:latest

helm lint helm/hello-world
helm template hello helm/hello-world
helm upgrade --install hello ./helm/hello-world
```

`--platform linux/amd64` is required when building on Apple Silicon. An ARM image on a t3.small node produces `exec format error` and a crash loop.

### Retrieve the endpoint

```bash
kubectl get ingress
```

The `ADDRESS` column populates within two to three minutes. If it remains empty:

```bash
kubectl describe ingress hello | tail -20
```

| Symptom | Layer at fault |
|---|---|
| `i/o timeout` | Security group — the packet was dropped |
| `403` / `AccessDenied` | IAM — the request reached AWS and was refused |
| No events at all | No controller claimed the Ingress — check `ingressClassName` |

---

## Infrastructure

### Networking

A VPC spanning two availability zones with public and private subnets in each; EKS requires a minimum of two AZs.

Three subnet tags are load-bearing:

| Tag | Purpose |
|---|---|
| `kubernetes.io/cluster/<name>` | Associates the subnet with the cluster |
| `kubernetes.io/role/elb` | Marks public subnets for internet-facing load balancers |
| `kubernetes.io/role/internal-elb` | Marks private subnets for internal load balancers |

The AWS Load Balancer Controller performs subnet selection by reading these tags. Their absence is the most common cause of an Ingress that never receives an address.

### Identity and access

Six roles, each scoped to a single consumer:

| Role | Consumer | Grants |
|---|---|---|
| `eks-cluster-role` | EKS control plane | Cluster resource management |
| `eks-node-role` | Worker nodes | Worker, CNI and ECR read policies |
| `jenkins-role` | Build server (EC2) | ECR push, `eks:DescribeCluster` |
| `alb-controller-role` | ServiceAccount via IRSA | Load balancer provisioning |
| `cluster-autoscaler-role` | ServiceAccount via IRSA | Auto Scaling group modification |
| `github-actions-role` | Workflow run via OIDC | ECR push |

Three credential mechanisms, no static keys:

```
EC2 instance profile  →  build server
IRSA                  →  in-cluster controllers
GitHub OIDC           →  workflow runs
```

Each follows the same pattern: the caller presents a signed token, AWS validates the signature against a registered identity provider, evaluates a trust policy, and returns temporary credentials.

Two distinctions worth stating precisely:

| | Defines |
|---|---|
| Trust policy | **Who** may assume the role |
| Permissions policy | **What** the role may then do |

A trust policy accepts only `Action`, `Effect` and `Principal`. Including a `Resource` field returns `MalformedPolicyDocument`.

An `aws_iam_instance_profile` resource does not attach itself. The `aws_instance` must reference it explicitly, or the host has no credentials at all.

### Cluster

```hcl
access_config {
  authentication_mode                         = "API_AND_CONFIG_MAP"
  bootstrap_cluster_creator_admin_permissions = true
}
```

EKS authorizes on two levels: IAM governs access to the AWS EKS API, Kubernetes RBAC governs actions inside the cluster. The bridge was historically the `aws-auth` ConfigMap, which required cluster access in order to grant cluster access. The access-entry API replaces it with standard AWS API calls, allowing `aws_eks_access_entry` to grant permissions declaratively in Terraform.

Node group:

```hcl
scaling_config {
  min_size     = 1
  max_size     = 4
  desired_size = 1
}
instance_types = ["t3.small"]
ami_type       = "AL2023_x86_64_STANDARD"
```

`ami_type` is explicit because Amazon Linux 2 EKS AMIs are no longer published for current Kubernetes versions.

Two tags make the node group's Auto Scaling group discoverable:

```
k8s.io/cluster-autoscaler/enabled
k8s.io/cluster-autoscaler/tech_challenge_2_eks
```

### Security groups

The build server's group is declared explicitly. The cluster and load balancer groups are created and managed by EKS and the load balancer controller respectively.

One rule is added manually:

```hcl
resource "aws_security_group_rule" "cluster_api_from_jenkins" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main_eks_cluster.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.jenkins_sg.id
}
```

The EKS-created cluster security group ships with a single inbound rule permitting traffic from itself. Worker nodes share that group and therefore reach the control plane; the build server does not, and its traffic is dropped — presenting as `dial tcp 10.0.x.x:443: i/o timeout`.

Referencing `source_security_group_id` rather than a CIDR keeps the rule valid if the build server is replaced with a new private address.

> An `aws_security_group` declared without an `egress` block receives no outbound rules. The console applies allow-all by default; Terraform does not.

---

## Continuous delivery — Jenkins (`main`)

### Build server provisioning

Ansible configures the host from a control node inside the same VPC:

```
Ansible control node
        │  SSH over the private network
        ▼
Build server
        ├── Docker engine
        ├── Jenkins (container)
        └── aws-cli, kubectl, helm — installed inside the container
```

Jenkins runs as a container, so every tool the pipeline invokes must exist inside it rather than on the host.

`scripts/verify-connectivity.sh` validates the chain before any pipeline is written. Each check isolates one layer:

| Check | Validates | Failure indicates |
|---|---|---|
| `aws sts get-caller-identity` | Credentials reach the container | Missing instance profile, or metadata hop limit of 1 |
| `aws eks update-kubeconfig` | `eks:DescribeCluster` granted | IAM permissions |
| `kubectl get nodes` | RBAC and network path to the API server | Access entry, or the cluster security group rule |
| Tool versions | Configuration management succeeded | Ansible playbook |

### Pipeline

```groovy
environment {
    AWS_REGION   = 'us-east-1'
    ACCOUNT_ID   = '730335577638'
    ECR_REPO     = "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/tech_challenge_2-ecr-app"
    CLUSTER_NAME = 'tech_challenge_2_eks'
    RELEASE_NAME = 'hello'
    IMAGE_TAG    = "${env.BUILD_NUMBER}"
}
```

| Stage | Action |
|---|---|
| Checkout | `checkout scm` — repository and credentials configured on the job, not in the Jenkinsfile |
| Build | Tags the image with the build number, giving every build a traceable artifact |
| Authenticate | Temporary ECR token from the instance role, piped to `docker login --password-stdin` |
| Push | Publishes both the build tag and `:latest` |
| Deploy | `update-kubeconfig`, then `helm upgrade --install --wait` |

```groovy
helm upgrade --install $RELEASE_NAME ./helm/hello-world \
  --set image.repository=$ECR_REPO \
  --set image.tag=$IMAGE_TAG \
  --wait --timeout 5m

kubectl rollout status deployment/$RELEASE_NAME --timeout=5m
```

| Flag | Effect |
|---|---|
| `--install` | Installs on first run, upgrades thereafter — a single idempotent command |
| `--set` | Overrides chart values with this build's image |
| `--wait` | Blocks until pods report ready |
| `rollout status` | Fails the build if the new pods never become healthy |

`RELEASE_NAME` must match the existing release. A different name produces a second complete object set — including a second load balancer — rather than an upgrade.

The `post { always { … } }` block prunes dangling images and clears the workspace to protect the host's disk.

### Webhook

```
Payload URL:  http://<build-server-ip>:8080/github-webhook/
Content type: application/x-www-form-urlencoded
Events:       Push only
```

The trailing slash is required. The job must have **GitHub hook trigger for GITScm polling** enabled. A webhook-triggered build reports `Started by GitHub push by <user>`. An Elastic IP keeps the URL stable across host restarts.

---

## Continuous delivery — GitOps (`gitops`)

```
Jenkins              →  pushes state into the cluster from outside
Actions + Argo CD    →  the cluster pulls state from git
```

### GitHub Actions

```yaml
permissions:
  id-token: write    # issue the OIDC token
  contents: write    # commit the updated tag
```

```yaml
on:
  push:
    branches: [gitops]
    paths:
      - 'app/**'
      - '.github/workflows/build.yml'
```

The `paths` filter prevents recursion: the workflow's own commit to `values.yaml` does not match, so it cannot retrigger itself.

```yaml
- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ env.ROLE_ARN }}
    aws-region: ${{ env.AWS_REGION }}
```

The final step is what distinguishes GitOps from ordinary automation:

```bash
sed -i "s|^  tag: .*|  tag: \"${IMAGE_TAG}\"|" helm/hello-world/values.yaml
git commit -m "ci: image tag ${IMAGE_TAG}"
git push
```

The workflow never contacts the cluster. It records the desired state in git and exits.

### Argo CD

```yaml
spec:
  source:
    repoURL: https://github.com/FaboCloudsurf/Tech_challenge_2.git
    targetRevision: gitops
    path: helm/hello-world
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

`selfHeal` is what makes git authoritative — a manual `kubectl edit` is detected as drift and reverted, leaving a commit as the only way to change the running state. `prune` removes objects deleted from the repository.

The Application is named `hello` so that rendered object names match the existing Helm release and are adopted rather than duplicated.

Observed sync cycle:

```
Synced     / Healthy       steady state
   ↓
OutOfSync  / Healthy       new tag detected in git
   ↓
Synced     / Progressing   applied, waiting on the new pod
   ↓
Synced     / Healthy       rollout complete
```

Images are tagged with the 7-character commit SHA, so any running pod traces to the commit that produced it:

```
…/tech_challenge_2-ecr-app:06f3e1a
```

> Pushes to `gitops` require `git pull --rebase` first — the workflow commits to the same branch, so the remote advances independently.

---

## Autoscaling

| Target | Implementation |
|---|---|
| 1 node minimum, 4 maximum | Node group `min_size = 1`, `max_size = 4` |
| t3.small instances | `instance_types = ["t3.small"]` |
| One pod per node | `topologySpreadConstraints` on `kubernetes.io/hostname` |
| Three pods per node maximum | HPA `maxReplicas: 12` (4 nodes × 3) |
| Scale at 50% CPU **or** 50% memory | HPA `autoscaling/v2`, two resource metrics |

`autoscaling/v2` is required — `v1` supports a single CPU metric only. With two metrics defined, whichever crosses the threshold first triggers scale-up; scale-down requires both to fall below target.

Percentages are evaluated against `resources.requests`:

```
Target: 50% CPU
   ↓
50% of the request (100m)
   ↓
= 50m per pod
```

Without `requests`, the HPA reports `<unknown>` and never scales.

### Load test

```bash
siege -c 100 -t 5m http://<alb-endpoint>/
```

| Metric | Result |
|---|---|
| Transactions | 424,902 |
| Availability | 100.00% |
| Elapsed | 300.72 s |
| Response time | 70.72 ms |
| Transaction rate | 1,412.95 /s |
| Concurrency | 99.93 |
| Failed transactions | 3 |
| Longest / shortest | 1,120 ms / 30 ms |

Three failures across 424,902 requests — 99.9993% success — during a window in which pods were actively being created and terminated.

Observed response:

```
CPU     1%  →  137%  →  295%  →  392%     (target 50%)
Pods    1   →  3     →  6     →  12       (maxReplicas)
Nodes   1   →  2
```

Nodes stabilized at two rather than four, which is correct. Twelve pods requesting 100m each total 1.2 vCPU; two t3.small instances supply four. The autoscaler provisions only what pending pods require — `max_size = 4` provides headroom rather than a target.

---

## Cost management

The environment is scaled to zero between working sessions.

```bash
# Suspend
aws eks update-nodegroup-config \
  --cluster-name tech_challenge_2_eks \
  --nodegroup-name tech_challenge_2-eks-node-group \
  --scaling-config minSize=0,maxSize=4,desiredSize=0

aws ec2 stop-instances --instance-ids <build-server-id> <control-node-id>

# Resume
aws eks update-nodegroup-config \
  --cluster-name tech_challenge_2_eks \
  --nodegroup-name tech_challenge_2-eks-node-group \
  --scaling-config minSize=1,maxSize=4,desiredSize=1

aws ec2 start-instances --instance-ids <build-server-id> <control-node-id>
```

`maxSize` must remain ≥ 1; only `minSize` and `desiredSize` may be zero. Add-on pods are rescheduled automatically when a node returns — nothing requires reinstallation.

Components that bill continuously and cannot be suspended without deletion:

| Component | Approximate daily cost |
|---|---|
| EKS control plane | $2.40 |
| NAT Gateway | $1.08 |
| Application Load Balancer | $0.54 |

---



Version tolerance differs by component:

```
metrics-server      version-tolerant
ALB controller      version-tolerant
Cluster Autoscaler  must match the cluster's major.minor
```

The generalizable lesson:

> Configuration describes what should happen. Runtime describes what did. When a check fails and both sides appear correct, stop re-reading configuration and print what is actually being compared.

| Layer | Authoritative source |
|---|---|
| GitHub OIDC | The decoded `sub` claim from a live token |
| AWS IAM | CloudTrail event JSON |
| Kubernetes RBAC | `kubectl auth can-i --as=<principal>` |
| Any controller | Its own status object |

---

## Teardown

```bash
helm uninstall hello
kubectl delete -n argocd -f argocd/application.yaml
```

Remove the Helm release before destroying infrastructure. The load balancer and its security groups were created by the controller, not by Terraform, and Terraform cannot delete the VPC while they remain — producing `DependencyViolation`.

If the cluster has already been destroyed, remove the orphaned resources directly:

```bash
aws elbv2 delete-load-balancer --load-balancer-arn <arn>
aws ec2 delete-security-group --group-id <k8s-traffic-…>
aws ec2 delete-security-group --group-id <k8s-default-…>
```

Delete the node-traffic group first; it holds a rule referencing the load balancer's group.

```bash
cd terraform
terraform destroy
```

---

## Author

**Fabian Brown** — AWS Cloud & DevOps Engineer
Region `us-east-1` · Cluster `tech_challenge_2_eks` · Kubernetes `1.31`
