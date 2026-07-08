# Grabs the latest optimized x86_64 base AMI from Red Hat's repository
data "aws_ami" "rhel9" {
  most_recent = true
  owners      = ["309956199498"] # Red Hat Account ID

  filter {
    name   = "name"
    values = ["RHEL-9.*_HVM-*-x86_64-*"]
  }
}

data "aws_ami" "rhel10" {
  most_recent = true
  owners      = ["309956199498"] # Official Red Hat Account ID remains identical

  filter {
    name   = "name"
    values = ["RHEL-10.*_HVM-*-x86_64-*"]
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
  ami                    = data.aws_ami.rhel10.id
  instance_type          = "m6i.xlarge" 
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
    Name        = "quay"
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
    Name        = "jenkins"
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
