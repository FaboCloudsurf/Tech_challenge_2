# Data source for latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true  #doesn't return a fixed AMI ID — it re-asks AWS "what's newest right now" every single time you run plan.
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Jenkins Master EC2 Instance
resource "aws_instance" "jenkins_master" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.jenkins_instance_type
  key_name      = var.key_name
  count         = 1

  iam_instance_profile = aws_iam_instance_profile.jenkins_instance_profile.name


    lifecycle {
    ignore_changes = [ami]  #pinned AMI, ignore drift to avoid forced replacement
  }

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  subnet_id              = aws_subnet.public_subnet[0].id

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name        = "${var.project_name}-jenkins-master-${count.index + 1}"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic IP for Jenkins Master
resource "aws_eip" "eip_jenkins_master" {
  instance = aws_instance.jenkins_master[count.index].id 
  domain   = "vpc"
  count = 1

  tags = {
    Name        = "${var.project_name}-jenkins-master-eip-${count.index + 1}"
    Environment = var.environment
  }
} 

resource "aws_instance" "ansible_master" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = var.ansible_instance_type
  key_name      = var.key_name

   lifecycle {
    ignore_changes = [ami]  #pinned AMI, ignore drift to avoid forced replacement

  }

  vpc_security_group_ids = [aws_security_group.jenkins_sg.id]
  subnet_id              = aws_subnet.public_subnet[0].id

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name        = "ansible Master"
    Environment = var.environment
    Project     = var.project_name
  }
}



