resource "aws_security_group" "jenkins_sg" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = aws_vpc.main_vpc.id

   lifecycle {
    create_before_destroy = true
  }

  ingress {
    description = "SSH from inside the VPC (Ansible control node)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }


  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "Jenkins Web UI from my IP"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  ingress {
    description = "GitHub webhook delivery"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["140.82.112.0/20", "143.55.64.0/20", "192.30.252.0/22"]    #GitHub's servers. Needed on 8080 so webhook deliveries can reach Jenkins when you push.
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-jenkins-sg2"
    Environment = var.environment
  }
}

#Added later on due to kubernetes created sg not listing jenkins port 443
resource "aws_security_group_rule" "cluster_api_from_jenkins" {
  type                     = "ingress"
  description              = "Allow Jenkins to reach the EKS API server"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_eks_cluster.main_eks_cluster.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.jenkins_sg.id
}