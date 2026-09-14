variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "project_name" {
  type    = string
  default = "tech_challenge_2"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "cluster_name" {
  type    = string
  default = "tech_challenge_2_eks"
}

variable "key_name" {
  type    = string
  default = "1_percent_keypair517"
}

variable "node_instance_type" {
  type    = string
  default = "t3.small"
}   

variable "jenkins_instance_type" {
  type    = string
  default = "t3.medium"
}   

variable "ansible_instance_type" {
  type    = string
  default = "t3.small"
}

 variable "kubernetes_version"  {
  type    = string
  default = "1.31"
}

 variable "node_desired_size"  {
  type = number
  default = 1
 }

 variable "node_max_size"  {
  type = number
  default = 4
 }

 variable "node_min_size"  {
  type = number
  default = 1
 }

variable "my_ip_cidr"  {
  type = string
  default = "67.83.164.99/32"
 }

