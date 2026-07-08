# Formally establishes the SSH key pair from your absolute path
resource "aws_key_pair" "bastion_key" {
  key_name   = "us-west-2-bastion-key"
  public_key = file("~/.ssh/aws_bastion_key.pub")

  tags = {
    Environment = "hack-a-thon"
  }
}

# Creates the requested specific security group wrapper
resource "aws_security_group" "bastion_sg" {
  name        = "us-west-2-bastion-sg"
  description = "Security baseline for Image Mode infrastructure control plane"
  vpc_id      = module.vpc.vpc_id

  # Inbound Rules
  ingress {
    description = "Allow administrative SSH ingress"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Tweak this to your specific public egress IP for security
  }

  ingress {
    description = "Allow VPC internal mesh communications"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # Outbound Rules
  egress {
    description = "Allow complete system outbound access for updates"
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
