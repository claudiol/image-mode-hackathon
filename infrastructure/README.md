Here is the complete infrastructure documentation formatted as a clean, production-ready `README.md` file. It incorporates the architectural layout, sizing decisions, and file breakdowns so anyone on your team can understand and stand up the environment.

---

# `README.md`

# AWS RHEL Image Mode Control Plane Infrastructure

This repository contains the declarative Terraform configurations required to provision a complete, self-contained Red Hat Enterprise Linux 9 engineering environment in AWS (`us-west-2`). This infrastructure acts as the foundational control plane and "OS Factory" used to compile, test, distribute, and monitor **RHEL Image Mode (`bootc`)** appliances.

## 📐 Architecture & Sizing Topology

The design isolates high-state management engines from stateless utilities, utilizing Red Hats official enterprise hardware prerequisites to ensure platform stability under high compilation loads.

| Host Name | Target Subnet Tier | Instance Type | Disk Allocation | Operational Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **bastion** | Public Subnet | `t3.small` | 200 GB GP3 | Public transit gateway, administrative jump box, and local proxy router. |
| **satellite** | Private Subnet | `m6i.2xlarge` | 500 GB GP3 | Red Hat Satellite Host. Sized to cache and synchronize RHEL 8/9 distribution repositories. |
| **IdM** | Private Subnet | `t3.medium` | 50 GB GP3 | Red Hat Identity Management (FreeIPA) Host providing unified Kerberos/LDAP identity. |
| **Quay** | Private Subnet | `m6i.xlarge` | 100 GB GP3 | Red Hat Quay Container Registry used to index and version custom `bootc` image layers. |
| **Jenkins** | Private Subnet | `c6i.xlarge` | 150 GB GP3 | Compute-optimized CI/CD engine running high-load `bootc-image-builder` pipelines. |
| **ansible** | Private Subnet | `m6i.xlarge` | 100 GB GP3 | Ansible Automation Platform (AAP) Host handling top-down infrastructure orchestration. |

## 🏗️ Core Configuration Files

### 1. `providers.tf`
Initializes the AWS infrastructure provider tracking contexts.

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-west-2"
}

```

### 2. `security.tf`

Establishes the key pair from your absolute local directory (`~/.ssh/aws_bastion_key`) and constructs the `us-west-2-bastion-sg` infrastructure firewall wrapper.

```hcl
# Formally establishes the SSH key pair from your local public key path
resource "aws_key_pair" "bastion_key" {
  key_name   = "us-west-2-bastion-key"
  public_key = file("~/.ssh/aws_bastion_key.pub")

  tags = {
    Environment = "hack-a-thon"
  }
}

# Creates the specific security group wrapper
resource "aws_security_group" "bastion_sg" {
  name        = "us-west-2-bastion-sg"
  description = "Security baseline for Image Mode infrastructure control plane"
  vpc_id      = module.vpc.vpc_id

  # Inbound Rules
  ingress {
    description = "Allow administrative SSH ingress from anywhere to bastion"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  ingress {
    description = "Allow VPC internal mesh cross-talk communications"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Outbound Rules
  egress {
    description = "Allow complete system outbound access for repositories and updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "us-west-2-bastion-sg"
    Environment = "hack-a-thon"
  }
}

```

### 3. `network.tf`

Generates the core networking matrix utilizing the community module block, provisioning clean external access points and isolated internal backend tiers.

```hcl
data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "us-west-imagemode-vpc"
  cidr = "10.20.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnets  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]

  # Standard operational routing architecture
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Environment = "hack-a-thon"
  }
}

```

### 4. `instances.tf`

Allocates the instances based on Red Hat specifications. The `bastion` host explicitly enforces public IP addressing.

```hcl
# Grabs the latest optimized x86_64 base AMI from Red Hat's repository
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat Account ID

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
}

# 1. BASTION (Public Transit Gateway Host)
resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.rhel9.id
  instance_type               = "t3.small"
  subnet_id                   = module.vpc.public_subnets[0] # Assigned to public subnet tier
  key_name                    = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  associate_public_ip_address = true # ENFORCES EXTERNAL PUBLIC IP ASSIGNMENT

  root_block_device {
    volume_size           = 200
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "bastion"
    Environment = "hack-a-thon"
  }
}

# 2. SATELLITE SERVER
resource "aws_instance" "satellite" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "m6i.2xlarge" # 8 vCPU / 32GB RAM Requirement
  subnet_id              = module.vpc.private_subnets[0]
  key_name               = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  root_block_device {
    volume_size           = 500 # Mandatory layout space for distribution repositories
    volume_type           = "gp3"
    iops                  = 3000
    throughput            = 125
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "satellite"
    Environment = "hack-a-thon"
  }
}

# 3. IDENTITY MANAGEMENT (IdM)
resource "aws_instance" "idm" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "t3.medium" # 2 vCPU / 4GB RAM Standard
  subnet_id              = module.vpc.private_subnets[1]
  key_name               = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "IdM"
    Environment = "hack-a-thon"
  }
}

# 4. RED HAT QUAY
resource "aws_instance" "quay" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "m6i.xlarge" # 4 vCPU / 16GB RAM Standard
  subnet_id              = module.vpc.private_subnets[2]
  key_name               = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "Quay"
    Environment = "hack-a-thon"
  }
}

# 5. JENKINS BUILD ENGINE
resource "aws_instance" "jenkins" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "c6i.xlarge" # Compute Optimized for layer compiling
  subnet_id              = module.vpc.private_subnets[0]
  key_name               = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  root_block_device {
    volume_size           = 150 # Large scratch area for bootc-image-builder transformations
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "Jenkins"
    Environment = "hack-a-thon"
  }
}

# 6. ANSIBLE AUTOMATION PLATFORM (AAP)
resource "aws_instance" "ansible" {
  ami                    = data.aws_ami.rhel9.id
  instance_type          = "m6i.xlarge" # 4 vCPU / 16GB RAM Platform Standard
  subnet_id              = module.vpc.private_subnets[1]
  key_name               = aws_key_pair.bastion_key.key_name
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name        = "ansible"
    Environment = "hack-a-thon"
  }
}

```

### 5. `outputs.tf`

Compiles output markers for clean deployment visibility.

```hcl
output "public_bastion_ip" {
  value       = aws_instance.bastion.public_ip
  description = "The explicit public IPv4 address for your SSH proxy jumping"
}

output "internal_control_plane_ips" {
  value = {
    satellite = aws_instance.satellite.private_ip
    idm       = aws_instance.idm.private_ip
    quay      = aws_instance.quay.private_ip
    jenkins   = aws_instance.jenkins.private_ip
    ansible   = aws_instance.ansible.private_ip
  }
  description = "List of isolated private backend routing network nodes"
}

```

---

## 🚀 Execution & Operational Steps

### 1. Prerequisites Execution

Ensure your local SSH key assets exist at the exact target location required by `security.tf`:

```bash
ls -l ~/.ssh/aws_bastion_key.pub

```

### 2. Provisioning Lifecycle

Execute the following standard command workflow to initialize and deploy the blueprint components:

```bash
# 1. Initialize working directory and pull modules
terraform init

# 2. Dry-run dry run mapping audit
terraform plan

# 3. Apply changes and spin up the control plane
terraform apply -auto-approve

```

### 3. Post-Deployment SSH Connectivity

Because the control plane infrastructure runs in the private subnets, connect to them via an **SSH Proxy Jump** utilizing the public Bastion host:

```bash
# To jump into the private Satellite host:
ssh -J ec2-user@<PUBLIC_BASTION_IP> ec2-user@<INTERNAL_SATELLITE_PRIVATE_IP> -i ~/.ssh/aws_bastion_key

```

```

```
