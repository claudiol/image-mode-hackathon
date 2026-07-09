# Image Mode Hackathon Lab Terraform Deployment

This Terraform project builds the AWS foundation required for the Image Mode Hackathon environment.

The deployment is designed to minimize manual steps. Terraform creates the infrastructure, generates bootstrap credentials, stores secrets securely in AWS Secrets Manager, creates DNS records, generates the Ansible inventory, and launches the lab configuration playbooks.

---

# What Terraform Builds

Terraform automatically creates:

- AWS VPC
- Public subnet
- Route53 Resolver infrastructure
- Security groups
- Elastic IP addresses
- RHEL 9 EC2 instances
- Public DNS records
- Red Hat IdM DNS forwarding
- AWS IAM roles
- AWS Secrets Manager secrets
- EC2 SSH bootstrap key
- Ansible inventory
- Lab bootstrap automation

The deployed environment contains:

- Red Hat Identity Management (IdM)
- Red Hat Satellite
- Red Hat Ansible Automation Platform (AAP)
- Red Hat Quay
- Image Builder server

---

# Architecture Overview

## DNS Design

AWS Route53 owns the parent domain:

```text
sandbox1234.opentlc.com
```

Red Hat IdM owns:

```text
lab.sandbox1234.opentlc.com
```

Generated hosts:

```text
idm-1.lab.sandbox1234.opentlc.com
aap-1.lab.sandbox1234.opentlc.com
satellite-1.lab.sandbox1234.opentlc.com
quay-1.lab.sandbox1234.opentlc.com
image-builder-1.lab.sandbox1234.opentlc.com
```

Route53 Resolver forwards the lab domain to IdM DNS.

---

# Key Files

## main.tf

Primary Terraform automation.

Responsible for:

- AWS networking
- DNS discovery
- EC2 deployment
- SSH key generation
- AWS Secrets creation
- IAM permissions
- Inventory generation
- Running Ansible bootstrap

Deployment flow:

```text
Terraform Apply

        |

Create AWS Infrastructure

        |

Generate Credentials

        |

Create Servers

        |

Generate Inventory

        |

Run Ansible Deployment
```

---

## variables.tf

Defines Terraform input variables:

Examples:

- AWS region
- DNS settings
- Server sizing
- Network ranges
- IdM users

Normally this file does not require changes.

Environment-specific settings belong in:

```text
terraform.tfvars
```

---

# terraform.tfvars Usage

This file controls the deployment.

Example:

```hcl
############################################################
# AWS Settings
############################################################

aws_profile = "image-mode-lab"

aws_region = "us-east-2"


############################################################
# Environment
############################################################

environment_name = "image-mode-lab"


############################################################
# DNS
############################################################

domain_name = ""

route53_zone_id = ""

create_public_dns_records = true


############################################################
# Networking
############################################################

vpc_cidr = "10.20.0.0/16"

public_subnet_cidr = "10.20.1.0/24"

resolver_subnet_cidr = "10.20.2.0/24"


############################################################
# Access
############################################################

ssh_allowed_cidr = "YOUR_PUBLIC_IP/32"


############################################################
# IdM Admin Users
############################################################

idm_users = [
  "student01",
  "admin01"
]
```

---

# IdM Temporary User Password

The lab creates IdM users automatically.

A temporary password is required for the initial login.

The Terraform variable is:

```text
idm_default_user_password
```

## Option 1: terraform.tfvars (Lab Usage)

For disposable lab environments you may set:

```hcl
############################################################
# IdM Temporary User Password
############################################################

# Initial password assigned to IdM users.
#
# Users should change this after first login.
#
# Do NOT commit terraform.tfvars containing real passwords.


idm_default_user_password = "YourPassword!"
```

To prevent accidental Git commits add:

```text
terraform.tfvars
*.tfvars
```

to:

```text
.gitignore
```

This prevents secret scanners such as GitGuardian from detecting committed credentials.

---

## Option 2: Environment Variable (Recommended)

For shared repositories or CI/CD:

```bash
export TF_VAR_idm_default_user_password='YourPassword!'
```

Terraform automatically maps this to:

```hcl
variable "idm_default_user_password"
```

No password is stored on disk.

---

# SSH Key Automation

No manual SSH key creation is required.

Terraform automatically:

1. Generates an RSA private key

2. Creates an AWS EC2 Key Pair:

```text
image-mode-lab-ssh-key
```

3. Creates:

```text
image-mode-lab-key.pem
```

Used by:

- Terraform bootstrap
- Ansible deployment

4. Stores the private key in AWS Secrets Manager:

```text
image-mode-lab/aws/ssh_private_key
```

Used later for:

- AAP machine credentials
- Automation jobs

---

# AWS Secrets Manager

Terraform creates required secrets automatically.

## IdM

```text
image-mode-lab/idm/admin_password

image-mode-lab/idm/directory_manager_password

image-mode-lab/idm/default_user_password
```

## AAP

```text
image-mode-lab/aap/controller_admin_password

image-mode-lab/aap/gateway_admin_password

image-mode-lab/aap/vault_password
```

## Quay

```text
image-mode-lab/quay/db_password

image-mode-lab/quay/superuser_password
```

## SSH

```text
image-mode-lab/aws/ssh_private_key
```

---

# ⚠️ Important: AAP Installer Private S3 Bucket Access

AAP downloads its installer files from a private S3 bucket.

The deployment retrieves:

```text
ansible-automation-platform-containerized-setup-bundle-2.7-1.2-x86_64.tar.gz

manifest_AAP.zip
```

from:

```text
s3://aap-containerized-installers/2.7/
```

The AWS account running this lab must be allowed access.

Find your AWS Account ID:

```bash
aws sts get-caller-identity \
--profile image-mode-lab
```

Example:

```json
{
    "Account": "123456789012"
}
```

Add that account to the S3 bucket policy:

```json
{
    "Sid": "AllowLabAccountDownloadAAPInstaller",
    "Effect": "Allow",
    "Principal": {
        "AWS": "arn:aws:iam::123456789012:root"
    },
    "Action": [
        "s3:GetObject"
    ],
    "Resource": [
        "arn:aws:s3:::aap-containerized-installers/2.7/*"
    ]
}
```

Replace:

```text
123456789012
```

with the AWS Account ID running Terraform.

Terraform creates the EC2 IAM role permissions automatically, but the bucket must trust the account.

Missing this step causes:

```text
AccessDenied
```

during AAP deployment.

---

# Red Hat Credentials

Do not store Red Hat credentials in Git.

Use environment variables:

```bash
export TF_VAR_redhat_org_id="123456"

export TF_VAR_redhat_aap_activation_key="activation-key"

export TF_VAR_redhat_registry_username="username"

export TF_VAR_redhat_registry_password="password"
```

---

# Deploy The Lab

## 1. Configure AWS CLI

```bash
aws configure \
--profile image-mode-lab
```

Verify:

```bash
aws sts get-caller-identity \
--profile image-mode-lab
```

---

## 2. Initialize Terraform

```bash
terraform init
```

---

## 3. Review Changes

```bash
terraform plan \
-out lab.tfplan
```

---

## 4. Deploy

```bash
terraform apply lab.tfplan
```

---

# Deployment Flow

```text
terraform apply

        |

Create AWS Network

        |

Generate Secrets

        |

Generate SSH Key

        |

Deploy Servers

        |

Configure DNS

        |

Generate inventory.ini

        |

Run Ansible Playbooks
```

---

# Generated Inventory

Terraform creates:

```text
inventory.ini
```

Example:

```ini
[idm]

idm-1.lab.example.com ansible_host=1.2.3.4


[aap]

aap-1.lab.example.com ansible_host=1.2.3.5
```

---

# Connecting To Servers

View generated SSH commands:

```bash
terraform output ssh_commands
```

Example:

```bash
ssh \
-i image-mode-lab-key.pem \
ec2-user@SERVER_PUBLIC_IP
```

After IdM deployment:

- Users authenticate through IdM
- SSH keys are managed through IdM
- Bootstrap key is retained for automation

---

# Useful Outputs

```bash
terraform output
```

Examples:

```text
aap_url

quay_url

satellite_url

idm_fqdn

lab_ssh_private_key_secret_name
```

---

# Destroy The Lab

Remove everything:

```bash
terraform destroy
```

Deletes:

- EC2 instances
- EBS volumes
- DNS records
- Resolver configuration
- IAM resources
- Secrets
- Networking

---

# Security Notes

This is designed for automated labs.

Production recommendations:

- Use remote encrypted Terraform state
- Protect Terraform state access
- Rotate generated credentials
- Restrict SSH CIDRs
- Avoid committing terraform.tfvars
- Store production secrets externally