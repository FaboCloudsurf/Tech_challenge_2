#!/usr/bin/env bash
# Verifies the Jenkins container can authenticate to AWS and reach the EKS cluster.
# Run on the Jenkins EC2 host.

set -euo pipefail               #the script stops at the first failure instead of printing errors and ending with "All checks passed."

CLUSTER="tech_challenge_2_eks"
REGION="us-east-1"

run() { sudo docker exec jenkins bash -c "$1"; }

echo "==> 1. AWS identity"
run "aws sts get-caller-identity"

echo
echo "==> 2. Build kubeconfig"
run "aws eks update-kubeconfig --region $REGION --name $CLUSTER"

echo
echo "==> 3. Cluster access"
run "kubectl get nodes"

echo
echo "==> 4. Tool versions"
run "aws --version; kubectl version --client; helm version --short"

echo
echo "All checks passed."





