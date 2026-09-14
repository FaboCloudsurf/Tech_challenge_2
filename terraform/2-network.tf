#NETWORK
# VPC Creates a Virtual Private Cloud (your own private network section inside AWS).
resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true #Enables the AWS DNS resolver so instances can resolve domain names.

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

# Public subnets
# These are the parts of your network that can talk directly to the internet.Like web servers or load balancers that need to be reachable from outside.
# Anything placed here can be reached directly from the internet.
resource "aws_subnet" "public_subnet" {
  count             = 2
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = count.index == 0 ? "us-east-1a" : "us-east-1b"

  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    "kubernetes.io/role/elb"                    = "1" #put internet-facing load balancers here.
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" #this subnet belongs to that cluster.
  }
}

# Private subnets
# Nothing here is directly reachable from the internet - only through the load balancer.
# These are the safer, hidden parts of your network. Servers here cannot be reached directly from the internet. They can still go out to the 
# internet (through the NAT Gateway) to download updates.
resource "aws_subnet" "private_subnet" {
  count             = 2
  vpc_id            = aws_vpc.main_vpc.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone = count.index == 0 ? "us-east-1a" : "us-east-1b"

  tags = {
    Name        = "${var.project_name}-private-subnet-${count.index + 1}"
    Environment = var.environment
    "kubernetes.io/role/internal-elb"           = "1"   #put internal-only load balancers here
    "kubernetes.io/cluster/${var.cluster_name}" = "shared" #this subnet belongs to that cluster.

  }
}

# Internet Gateway
# This is the main doorway that connects your entire VPC to the public internet.
# Without it, nothing inside the VPC — public or private — could send or receive any outside traffic at all, no matter what else is configured.
resource "aws_internet_gateway" "main_ig" {
  vpc_id = aws_vpc.main_vpc.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

# Reserves one fixed, unchanging public IP address, specifically so the NAT Gateway below has a stable address to use.
resource "aws_eip" "main_nat" {
  domain = "vpc" # just specifies this IP is for use inside a VPC (
  tags = {
    Name        = "${var.project_name}-nat-eip"
    Environment = var.environment
  }
}

# This gives private servers a way to reach the internet (for updates, package downloads, etc.) without letting the internet reach them.
# Lets your private-subnet resources (which have no public IP of their own) reach out to the internet — for example, to download container images — 
# while staying completely unreachable from the outside world themselves. It has to sit inside a public subnet itself (aws_subnet.public[0]), since  
# it needs direct internet access to do its job. 
resource "aws_nat_gateway" "main_nig" {
  allocation_id = aws_eip.main_nat.id
  subnet_id     = aws_subnet.public_subnet[0].id

  tags = {
    Name        = "${var.project_name}-nat-gateway"
    Environment = var.environment
  }

  depends_on = [aws_internet_gateway.main_ig] #depends_on forces it to wait until the Internet Gateway actually exists first.
}

# The "directions" for public subnets: any outbound traffic goes straight out through the Internet Gateway.
# A set of "directions" attached to the public subnets.
# These are the traffic rule books that tell data where to go.
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main_ig.id # Send it out through the main internet doorway
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

# Same concept, but for private subnets: outbound traffic gets routed through the NAT Gateway instead of directly out the Internet Gateway — 
# keeping these resources hidden while still letting them reach the internet.
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main_nig.id # Send it out through the NAT Gateway instead
  }

  tags = {
    Name        = "${var.project_name}-private-rt"
    Environment = var.environment
  }
}

# Route Table Associations
# These simply attach the rule books above to the correct subnets.
resource "aws_route_table_association" "public_rta" {
  count          = 2
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "private_rta" {
  count          = 2
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_rt.id
} 

#This code defines a VPC with public and private subnets in two availability zones, sets up an internet gateway and NAT gateway for outbound access, 
#and configures route tables and associations so each subnet has proper routing. It builds a complete, structured network foundation for AWS 
#resources.

# Nat Gateway: hidden resources (like your ECS tasks) reach out to the internet - without ever being reachable FROM the internet themselves. Must 
# live in a public subnet.

# They exist because the AWS Load Balancer Controller doesn't read your Terraform. When you create an Ingress, it asks AWS "which subnets in this 
# VPC am I allowed to use?" and picks by tag. No tag, no ALB — it fails with a subnet discovery error.
