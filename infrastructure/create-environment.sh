#!/bin/bash
# 1. Initialize the directory and download the latest AWS provider and VPC modules
terraform init --upgrade

# 2. Validate your code syntax and configurations to catch typos early
terraform validate

# 3. Preview the infrastructure plan to verify exactly what resources AWS will build
terraform plan

# 4. Apply the configuration and build the active VPC, subnets, and gateways in your AWS account
terraform apply

