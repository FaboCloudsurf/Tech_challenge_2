resource "aws_eks_cluster" "main_eks_cluster" {
  name = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = "API_AND_CONFIG_MAP"  #how IAM identities get mapped to Kubernetes permissions.
    bootstrap_cluster_creator_admin_permissions = true  #whoever runs terraform apply gets cluster-admin automatically. Without it, you'd create a cluster you can't access with kubectl.
  }

  vpc_config {
    subnet_ids              = concat(aws_subnet.public_subnet[*].id, aws_subnet.private_subnet[*].id) #which subnets the cluster can use.concat() joins two lists into one, and [*].id pulls the ID out of each subnet. So this hands EKS all four subnets, public and private.
    endpoint_public_access  = true  #can reach the cluster's API from the internet. That's how kubectl on your laptop connects.
    endpoint_private_access = true  #the cluster's API is also reachable from inside the VPC. That's how worker nodes talk to the control plane without going out to the internet and back
    
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"] #This tells EKS which types of control-plane logs to send to CloudWatch.
  #api = requests to the cluster API,Logs activity involving the Kubernetes API server
  #audit = who did what,Records who did what to the Kubernetes cluster
  #authenticator = login attempts (which IAM role got rejected when kubectl says Unauthorized).Logs authentication activity—who/what is trying to access the cluster


  # Ensure that IAM Role permissions are created before and deleted
  # after EKS Cluster handling. Otherwise, EKS will not be able to
  # properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy_attach
  ]

  tags = {
    Name = var.cluster_name
    Environment = var.environment
  }
}



#the group of EC2 instances that run your pods.A node is essentially an EC2 instance that Kubernetes can use to run your application pods.
resource "aws_eks_node_group" "main_eks_node_group" {
  cluster_name    = aws_eks_cluster.main_eks_cluster.name   #"Put this node group into this EKS cluster."
  node_group_name = "${var.project_name}-eks-node-group"    #Gives the node group a name.
  node_role_arn   = aws_iam_role.eks_nodes_role.arn         #Specifies the IAM role that the worker nodes use.
  subnet_ids      = aws_subnet.private_subnet[*].id    #where the nodes live. Private subnets, so they're not directly reachable from the internet.
  ami_type = "AL2023_x86_64_STANDARD" #added
  #[*] Get the ID of every subnet in this collection.

  instance_types = [var.node_instance_type]
  capacity_type  = "ON_DEMAND"      #default
  disk_size      = 20               #default


  scaling_config {
    desired_size = var.node_desired_size    #how many to start with.
    max_size     = var.node_max_size        #the max amount of node
    min_size     = var.node_min_size        ##the minimum amount of node
  }

  update_config {
    max_unavailable = 1                     #during a node upgrade, only take one node down at a time.Controls how many nodes can be unavailable during a node-group update.
  }

    labels = {
    role = "app"        #Labels allow Kubernetes to identify/group resources.Run this workload only on nodes with role=app.
  }

    tags = {
    Name        = "${var.project_name}-node-group"
    Environment = var.environment

    "k8s.io/cluster-autoscaler/enabled"             = "true"        #tells the Kubernetes Cluster Autoscaler that this node group can be considered for automatic scaling.
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"       #Associates the node group with your specific cluster for the Cluster Autoscaler.
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]       #Don't try to change the desired number of nodes if something outside Terraform changes it.
  }

  # Don't create the node group until these IAM permissions have been attached.
  # Ensure that IAM Role permissions are created before and deleted after EKS Node Group handling.
  # Otherwise, EKS will not be able to properly delete EC2 Instances and Elastic Network Interfaces.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy_attach,
    aws_iam_role_policy_attachment.node_cni_policy_attach,
    aws_iam_role_policy_attachment.node_ecr_policy_attach,
  ]
}

#registers an IAM role as a valid identity inside the cluster.Allowing Jenkins to access your EKS cluster using an IAM role.Jenkins is an identity that can access the cluster.
resource "aws_eks_access_entry" "jenkins_eks_access_entry" {
  cluster_name      = aws_eks_cluster.main_eks_cluster.name
  principal_arn     = aws_iam_role.jenkins_role.arn     #This identifies who is being granted access.
  #kubernetes_groups = ["group-1", "group-2"]
  type              = "STANDARD"                        #Specifies the type of EKS access entry.
}


#This connects Jenkins to an EKS access policy."Here is what Jenkins is allowed to do."
resource "aws_eks_access_policy_association" "jenkins_eks_access_policy_association" {
  cluster_name  = aws_eks_cluster.main_eks_cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"      #The permission
  principal_arn = aws_iam_role.jenkins_role.arn

  access_scope {
    type       = "cluster"              #admin across the whole cluster level rather than one Kubernetes namespace.
    #namespaces = ["example-namespace"]
  }
}