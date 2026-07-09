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

The lab uses a dedicated IdM managed DNS subdomain.

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

Route53 Resolver forwards:

```text
lab.sandbox1234.opentlc.com
```

queries to the IdM DNS server.

---

# Key Files

## main.tf

Primary Terraform automation.

Responsible for:

- Route53 discovery
- Network creation
- Server deployment
- SSH key generation
- Secrets creation
- IAM configuration
- DNS configuration
- Inventory generation
- Lab bootstrap execution

Deployment flow:

```text
Terraform Apply
       |
       v
AWS Infrastructure
       |
       v
Generate Credentials
       |
       v
Create Servers
       |
       v
Generate Inventory
       |
       v
Run Ansible Deployment
```

---

## variables.tf

Defines configurable Terraform inputs:

Examples:

- AWS region
- Environment name
- Network ranges
- DNS configuration
- Server sizing
- IdM users

Normally this file does not need modification.

User settings belong in:

```text
terraform.tfvars
```

---

# terraform.tfvars Usage

This file controls your deployment.

Example:

```hcl
############################################################
# AWS
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
# IdM Users
############################################################

idm_users = [
  "student01",
  "admin01"
]
```

---

# SSH Key Automation

Manual SSH key creation is not required.

Terraform automatically:

1. Generates a private key

2. Creates an AWS EC2 key pair

Example:

```text
image-mode-lab-ssh-key
```

3. Creates a local bootstrap key:

```text
image-mode-lab-key.pem
```

Used by:

- Terraform
- Initial Ansible deployment

4. Stores the key in AWS Secrets Manager:

```text
image-mode-lab/aws/ssh_private_key
```

Used later by:

- AAP machine credentials
- Automation jobs

---

# AWS Secrets Manager

Terraform creates the required lab secrets automatically.

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

The AAP deployment retrieves installation content from a private AWS S3 bucket.

The playbook downloads:

```text
ansible-automation-platform-containerized-setup-bundle-2.7-1.2-x86_64.tar.gz

manifest_AAP.zip
```

from:

```text
s3://aap-containerized-installers/2.7/
```

Because this bucket is private, the AWS account running the lab must be allowed access.

Before deployment, update the bucket policy with your AWS Account ID.

Find the account:

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

Add this account to the bucket policy:

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

with your AWS environment Account ID.

Terraform creates the AAP EC2 IAM permissions automatically, but the private S3 bucket must also trust the AWS account.

If this step is missed, AAP deployment fails with:

```text
AccessDenied
```

when downloading the installer.

---

# Sensitive Variables

Do not commit Red Hat credentials.

Export them instead:

```bash
export TF_VAR_redhat_org_id="123456"

export TF_VAR_redhat_aap_activation_key="activation-key"

export TF_VAR_redhat_registry_username="username"

export TF_VAR_redhat_registry_password="password"
```

Optional IdM default password:

```bash
export TF_VAR_idm_default_user_password='ChangeMe123!'
```

---

# Deploy The Lab

## 1. Configure AWS CLI

```bash
aws configure \
--profile image-mode-lab
```

Verify access:

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

## 3. Review Deployment

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
        v

Create AWS Network

        |
        v

Create Secrets

        |
        v

Generate SSH Key

        |
        v

Deploy RHEL Servers

        |
        v

Configure DNS

        |
        v

Generate inventory.ini

        |
        v

Clone Automation Repository

        |
        v

Run deploy-services.yml
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

Terraform outputs SSH commands:

```bash
terraform output ssh_commands
```

Example:

```bash
ssh \
-i image-mode-lab-key.pem \
ec2-user@SERVER_PUBLIC_IP
```

After IdM deployment, users authenticate through Red Hat IdM.

---

# Useful Outputs

View everything:

```bash
terraform output
```

Common outputs:

```text
aap_url

quay_url

satellite_url

idm_fqdn

lab_ssh_private_key_secret_name
```

---

# Destroy Lab

Remove all AWS resources:

```bash
terraform destroy
```

This removes:

- EC2 instances
- Volumes
- DNS records
- Resolver rules
- Secrets
- IAM roles
- Network resources

---

# Security Notes

This environment is intended as an automated lab.

For production:

- Store Terraform state remotely
- Encrypt Terraform state
- Restrict state access
- Rotate generated secrets
- Restrict SSH access
- Avoid committing terraform.tfvars containing secrets