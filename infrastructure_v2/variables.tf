############################################################
# AWS Settings
############################################################

variable "aws_profile" {
  type        = string
  default     = "image-mode-lab"
  description = "AWS CLI profile Terraform should use."
}

variable "aws_region" {
  type        = string
  default     = "us-east-2"
  description = "AWS region to deploy the lab into."
}

############################################################
# Environment Settings
############################################################

variable "environment_name" {
  type        = string
  default     = "image-mode-lab"
  description = "Name prefix used for AWS resource tags."
}

############################################################
# AWS Secrets Manager
############################################################

variable "secret_prefix" {
  type        = string
  default     = "image-mode-lab"
  description = "AWS Secrets Manager prefix containing lab bootstrap credentials."
}

############################################################
# DNS Settings
############################################################

variable "domain_name" {
  type        = string
  default     = ""
  description = "Base OpenTLC parent DNS domain. Leave blank to auto-discover the public sandbox*.opentlc.com Route53 hosted zone."
}

variable "opentlc_domain_suffix" {
  type        = string
  default     = "opentlc.com"
  description = "Domain suffix used when auto-discovering OpenTLC sandbox public hosted zones."
}

variable "create_public_dns_records" {
  type        = bool
  default     = true
  description = "Create public Route53 A records for instances in the parent public Route53 zone."
}

variable "route53_zone_id" {
  type        = string
  default     = ""
  description = "Optional public Route53 zone ID. If blank, Terraform looks up the public hosted zone by domain_name or auto-discovered domain."
}

############################################################
# Networking
############################################################

variable "vpc_cidr" {
  type        = string
  default     = "10.20.0.0/16"
  description = "CIDR block for the lab VPC."
}

variable "public_subnet_cidr" {
  type        = string
  default     = "10.20.1.0/24"
  description = "CIDR block for the main subnet where lab instances are deployed."
}

variable "resolver_subnet_cidr" {
  type        = string
  default     = "10.20.2.0/24"
  description = "Second subnet CIDR used by Route53 Resolver endpoint."
}

############################################################
# Access
############################################################

variable "ssh_allowed_cidr" {
  type        = string
  description = "Allowed CIDR for SSH bootstrap access."
}

############################################################
# AMI Settings
############################################################

variable "ami_id" {
  type        = string
  default     = ""
  description = "Optional RHEL AMI ID. Leave blank to auto-discover."
}

############################################################
# IdM Users
############################################################

variable "lab_users" {
  description = "Users created inside Red Hat IdM."

  type = map(object({
    first_name = string
    last_name  = string
    groups     = list(string)
  }))

  default = {
    student01 = {
      first_name = "Student"
      last_name  = "One"

      groups = [
        "developers",
        "quay-users"
      ]
    }

    instructor01 = {
      first_name = "Instructor"
      last_name  = "One"

      groups = [
        "linux-admins",
        "aap-admins",
        "satellite-admins",
        "quay-admins"
      ]
    }
  }
}

############################################################
# EC2 Server Definitions
############################################################

variable "servers" {
  description = "Server definitions for the RHEL Image Mode lab."

  type = map(object({
    count         = number
    instance_type = string
    root_volume   = number
    extra_volume  = number
  }))

  default = {
    idm = {
      count         = 1
      instance_type = "m6i.large"
      root_volume   = 80
      extra_volume  = 0
    }

    satellite = {
      count         = 1
      instance_type = "m6i.2xlarge"
      root_volume   = 200
      extra_volume  = 500
    }

    aap = {
      count         = 1
      instance_type = "m6i.xlarge"
      root_volume   = 120
      extra_volume  = 0
    }

    quay = {
      count         = 1
      instance_type = "m6i.large"
      root_volume   = 100
      extra_volume  = 300
    }

    image-builder = {
      count         = 1
      instance_type = "m6i.2xlarge"
      root_volume   = 120
      extra_volume  = 500
    }
  }
}

############################################################
# Red Hat Credentials
#
# Pass these with TF_VAR_* environment variables.
# Do not commit values to terraform.tfvars.
############################################################

variable "redhat_org_id" {
  type        = string
  description = "Red Hat organization ID."
  sensitive   = true
}

variable "redhat_aap_activation_key" {
  type        = string
  description = "Red Hat activation key for AAP/RHEL registration."
  sensitive   = true
}

variable "redhat_registry_username" {
  type        = string
  description = "registry.redhat.io username."
  sensitive   = true
}

variable "redhat_registry_password" {
  type        = string
  description = "registry.redhat.io password."
  sensitive   = true
}

############################################################
# IdM Admin Users
############################################################

variable "idm_users" {
  description = "Simple IdM users created as lab IdM administrators."
  type        = list(string)

  default = [
    "claudiol",
    "pduncan",
    "cpranava",
    "stripura"
  ]
}

variable "idm_default_user_password" {
  type        = string
  sensitive   = true
  description = "Temporary default password for initial IdM lab users."
}