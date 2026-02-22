# VPC with IPv6 primary, IPv4 fallback (dual-stack)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  # AWS-provided IPv6 CIDR block (only if not using BYOIP)
  assign_generated_ipv6_cidr_block = var.use_byoip_ipv6 ? false : true

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-vpc"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    }
  )
}

# BYOIP IPv6 CIDR Block Association (only if using BYOIP)
resource "aws_vpc_ipv6_cidr_block_association" "byoip" {
  count = var.use_byoip_ipv6 ? 1 : 0

  vpc_id          = aws_vpc.main.id
  ipv6_cidr_block = var.byoip_ipv6_cidr
  ipv6_pool       = var.byoip_ipv6_pool_id

  # Use either explicit CIDR or pool with netmask length
  ipv6_netmask_length = var.byoip_ipv6_cidr == null ? var.byoip_ipv6_netmask_length : null

  lifecycle {
    precondition {
      condition     = !var.use_byoip_ipv6 || var.byoip_ipv6_pool_id != null
      error_message = "byoip_ipv6_pool_id must be specified when use_byoip_ipv6 is true"
    }
  }
}

# Local value to get the correct IPv6 CIDR block
locals {
  vpc_ipv6_cidr_block = var.use_byoip_ipv6 ? aws_vpc_ipv6_cidr_block_association.byoip[0].ipv6_cidr_block : aws_vpc.main.ipv6_cidr_block
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-igw"
    }
  )
}

# Public Subnets (IPv6 primary, IPv4 dual-stack)
resource "aws_subnet" "public" {
  count                           = length(var.public_subnet_cidrs)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = var.public_subnet_cidrs[count.index]
  availability_zone               = var.availability_zones[count.index]
  map_public_ip_on_launch         = true
  # Automatically assign IPv6 addresses (primary)
  assign_ipv6_address_on_creation = true
  ipv6_cidr_block                 = cidrsubnet(local.vpc_ipv6_cidr_block, 8, count.index + 100)

  depends_on = [aws_vpc_ipv6_cidr_block_association.byoip]

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-public-subnet-${count.index + 1}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "kubernetes.io/role/elb"                    = "1"
    }
  )
}

# Private Subnets (IPv6 primary, IPv4 dual-stack)
resource "aws_subnet" "private" {
  count                           = length(var.private_subnet_cidrs)
  vpc_id                          = aws_vpc.main.id
  cidr_block                      = var.private_subnet_cidrs[count.index]
  availability_zone               = var.availability_zones[count.index]
  # Automatically assign IPv6 addresses (primary)
  assign_ipv6_address_on_creation = true
  ipv6_cidr_block                 = cidrsubnet(local.vpc_ipv6_cidr_block, 8, count.index)

  depends_on = [aws_vpc_ipv6_cidr_block_association.byoip]

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb"           = "1"
    }
  )
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat" {
  count  = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nat-eip-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-nat-${count.index + 1}"
    }
  )

  depends_on = [aws_internet_gateway.main]
}

# Public Route Table (IPv6 primary)
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # IPv6 default route (primary)
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.main.id
  }

  # IPv4 default route (fallback)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-public-rt"
    }
  )
}

# Public Route Table Association
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnet_cidrs)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Route Tables (IPv6 primary)
resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.main.id

  # IPv6 default route (primary) - egress-only for security
  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.main.id
  }

  # IPv4 default route (fallback) - via NAT Gateway
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-private-rt-${count.index + 1}"
    }
  )
}

# Private Route Table Association
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# Egress-Only Internet Gateway for IPv6 (primary egress for private subnets)
resource "aws_egress_only_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-eigw"
    }
  )
}

# Security Group for EKS Cluster
resource "aws_security_group" "eks_cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster"
  vpc_id      = aws_vpc.main.id

  # IPv6 egress (primary)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  # IPv4 egress (fallback)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

# Security Group for EKS Nodes
resource "aws_security_group" "eks_nodes" {
  name        = "${var.cluster_name}-nodes-sg"
  description = "Security group for EKS worker nodes (ML training)"
  vpc_id      = aws_vpc.main.id

  # IPv6 egress (primary)
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    ipv6_cidr_blocks = ["::/0"]
  }

  # IPv4 egress (fallback)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    var.tags,
    {
      Name                                        = "${var.cluster_name}-nodes-sg"
      "kubernetes.io/cluster/${var.cluster_name}" = "owned"
    }
  )
}

# Security Group Rules
resource "aws_security_group_rule" "cluster_inbound" {
  description              = "Allow nodes to communicate with the cluster API Server"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "nodes_internal" {
  description              = "Allow nodes to communicate with each other"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_nodes.id
}

resource "aws_security_group_rule" "nodes_cluster_inbound" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  type                     = "ingress"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_nodes.id
  source_security_group_id = aws_security_group.eks_cluster.id
}
