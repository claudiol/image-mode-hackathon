# main.tf

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_route53_zones" "public" {}

data "aws_route53_zone" "all_public" {
  for_each = toset(data.aws_route53_zones.public.ids)
  zone_id  = each.value
}

locals {
  all_public_zones = {
    for zone_id, zone in data.aws_route53_zone.all_public :
    zone_id => trimsuffix(zone.name, ".")
    if zone.private_zone == false
  }

  discovered_opentlc_zone_ids = [
    for zone_id, zone_name in local.all_public_zones :
    zone_id
    if can(regex("^sandbox[0-9]+\\.${replace(var.opentlc_domain_suffix, ".", "\\.")}$", zone_name))
  ]

  discovered_domain_name     = length(local.discovered_opentlc_zone_ids) == 1 ? local.all_public_zones[local.discovered_opentlc_zone_ids[0]] : ""
  discovered_route53_zone_id = length(local.discovered_opentlc_zone_ids) == 1 ? local.discovered_opentlc_zone_ids[0] : ""

  effective_domain_name  = trimspace(var.domain_name) != "" ? trimsuffix(var.domain_name, ".") : local.discovered_domain_name
  public_route53_zone_id = var.route53_zone_id != "" ? var.route53_zone_id : local.discovered_route53_zone_id

  parent_domain_name = local.effective_domain_name

  idm_dns_subdomain = "lab"
  idm_domain_name   = "${local.idm_dns_subdomain}.${local.parent_domain_name}"
  idm_realm_name    = upper(local.idm_domain_name)
}

resource "terraform_data" "validate_dns_discovery" {
  input = local.effective_domain_name

  lifecycle {
    precondition {
      condition = (
        !var.create_public_dns_records ||
        trimspace(var.domain_name) != "" ||
        length(local.discovered_opentlc_zone_ids) == 1
      )
      error_message = "Unable to auto-discover exactly one public sandbox*.opentlc.com Route53 hosted zone. Set domain_name explicitly."
    }

    precondition {
      condition     = !var.create_public_dns_records || local.effective_domain_name != ""
      error_message = "domain_name is blank and no usable public hosted zone was discovered."
    }

    precondition {
      condition = (
        !var.create_public_dns_records ||
        var.route53_zone_id != "" ||
        local.public_route53_zone_id != ""
      )
      error_message = "No public Route53 zone ID could be resolved. Set route53_zone_id explicitly."
    }
  }
}

locals {
  flattened_servers = merge([
    for role, cfg in var.servers : {
      for i in range(cfg.count) :
      "${role}-${i + 1}" => {
        role          = role
        index         = i + 1
        hostname      = "${role}-${i + 1}.${local.idm_domain_name}"
        instance_type = cfg.instance_type
        root_volume   = cfg.root_volume
        extra_volume  = cfg.extra_volume
      }
    }
  ]...)

  idm_server_keys = sort([
    for name, server in local.flattened_servers :
    name
    if server.role == "idm"
  ])

  primary_idm_key      = try(local.idm_server_keys[0], null)
  primary_idm_hostname = local.primary_idm_key != null ? local.flattened_servers[local.primary_idm_key].hostname : null
}

resource "terraform_data" "validate_idm_server" {
  input = local.idm_server_keys

  lifecycle {
    precondition {
      condition     = length(local.idm_server_keys) >= 1
      error_message = "var.servers must include an idm role with count >= 1 so Route53 Resolver can forward lab DNS queries to the selected primary IdM server."
    }
  }
}

data "aws_ami" "rhel9" {
  count       = var.ami_id == "" ? 1 : 0
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-9*_HVM-*-x86_64-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  selected_ami = var.ami_id != "" ? var.ami_id : data.aws_ami.rhel9[0].id

  aws_dns_resolver = cidrhost(aws_vpc.lab.cidr_block, 2)

  lab_ssh_private_key_filename = "${path.module}/image-mode-lab-key.pem"
  ansible_ssh_private_key_file = abspath(local.lab_ssh_private_key_filename)

  lab_ssh_private_key_secret_name = "${var.secret_prefix}/aws/ssh_private_key"
}

############################################################
# Generated SSH Key
############################################################

resource "tls_private_key" "lab_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "lab" {
  key_name   = "${var.environment_name}-ssh-key"
  public_key = tls_private_key.lab_ssh.public_key_openssh

  depends_on = [
    terraform_data.preflight_cleanup
  ]

  tags = {
    Name        = "${var.environment_name}-ssh-key"
    Environment = var.environment_name
  }
}

resource "local_sensitive_file" "lab_ssh_private_key" {
  filename        = local.lab_ssh_private_key_filename
  content         = tls_private_key.lab_ssh.private_key_pem
  file_permission = "0600"
}

############################################################
# AWS Secrets Manager
############################################################

locals {
  generated_secret_names = toset([
    "aap/postgresql_admin_password",
    "aap/gateway_admin_password",
    "aap/gateway_pg_password",
    "aap/controller_admin_password",
    "aap/controller_pg_password",
    "aap/hub_admin_password",
    "aap/hub_pg_password",
    "aap/eda_admin_password",
    "aap/eda_pg_password",
    "aap/automationmetrics_pg_password",
    "aap/automationmetrics_controller_read_pg_password",
    "aap/vault_password",
    "idm/admin_password",
    "idm/directory_manager_password",
    "satellite/admin_password",
    "quay/db_password",
    "quay/secret_key",
    "quay/database_secret_key",
    "quay/superuser_password",
    "quay/redis_password"
  ])

  static_secret_values = {
    "aap/gateway_admin_username" = "admin"
    "quay/superuser"             = "quayadmin"
    "quay/admin_access_token"    = "CHANGE_ME_AFTER_QUAY_DEPLOYMENT"
    "idm/default_user_password"  = var.idm_default_user_password
  }

  redhat_secret_values = {
    "redhat/org_id"             = var.redhat_org_id
    "redhat/aap_activation_key" = var.redhat_aap_activation_key
    "redhat/registry_username"  = var.redhat_registry_username
    "redhat/registry_password"  = var.redhat_registry_password
  }

  all_lab_secret_names = concat(
    [
      for secret_name in local.generated_secret_names :
      "${var.secret_prefix}/${secret_name}"
    ],
    [
      for secret_name, secret_value in local.static_secret_values :
      "${var.secret_prefix}/${secret_name}"
    ],
    [
      for secret_name, secret_value in local.redhat_secret_values :
      "${var.secret_prefix}/${secret_name}"
    ],
    [
      local.lab_ssh_private_key_secret_name
    ]
  )
}

############################################################
# Preflight Cleanup For Lab Rebuilds
############################################################

resource "terraform_data" "preflight_cleanup" {
  input = {
    cleanup_version  = 2
    environment_name = var.environment_name
    secret_prefix    = var.secret_prefix
    aws_region       = var.aws_region
    aws_profile      = var.aws_profile
    key_pair_name    = "${var.environment_name}-ssh-key"
    iam_role_name    = "${var.environment_name}-aap-role"
    iam_profile_name = "${var.environment_name}-aap-instance-profile"
    secrets          = local.all_lab_secret_names
  }

  provisioner "local-exec" {
    working_dir = path.module

    command = <<-EOT
      set -euo pipefail

      export AWS_REGION="${var.aws_region}"
      export AWS_DEFAULT_REGION="${var.aws_region}"

      if [ -n "${var.aws_profile}" ]; then
        export AWS_PROFILE="${var.aws_profile}"
      fi

      KEY_PAIR_NAME="${var.environment_name}-ssh-key"
      IAM_ROLE_NAME="${var.environment_name}-aap-role"
      IAM_PROFILE_NAME="${var.environment_name}-aap-instance-profile"

      echo "Preflight cleanup: duplicate-prone unmanaged lab resources"

      state_has() {
        terraform state list 2>/dev/null | grep -q "^$1$"
      }

      echo "Checking EC2 key pair: $KEY_PAIR_NAME"
      if state_has 'aws_key_pair.lab'; then
        echo "Skipping key pair cleanup because aws_key_pair.lab is already managed by Terraform state."
      else
        aws ec2 delete-key-pair \
          --key-name "$KEY_PAIR_NAME" \
          >/dev/null 2>&1 || true
      fi

      echo "Checking Secrets Manager secrets"
      if terraform state list 2>/dev/null | grep -q '^aws_secretsmanager_secret\.'; then
        echo "Skipping Secrets Manager cleanup because secrets are already managed by Terraform state."
      else
        cat > /tmp/image-mode-lab-secret-names.txt <<'EOF_SECRETS'
%{ for secret_name in local.all_lab_secret_names ~}
${secret_name}
%{ endfor ~}
EOF_SECRETS

        while IFS= read -r SECRET_NAME; do
          [ -n "$SECRET_NAME" ] || continue

          echo "Deleting unmanaged secret if it exists: $SECRET_NAME"

          aws secretsmanager delete-secret \
            --secret-id "$SECRET_NAME" \
            --force-delete-without-recovery \
            >/dev/null 2>&1 || true

          for i in $(seq 1 30); do
            if aws secretsmanager describe-secret \
              --secret-id "$SECRET_NAME" \
              >/dev/null 2>&1; then
              sleep 2
            else
              break
            fi
          done
        done < /tmp/image-mode-lab-secret-names.txt

        rm -f /tmp/image-mode-lab-secret-names.txt
      fi

      echo "Checking AAP IAM resources"

      if state_has 'aws_iam_instance_profile.aap'; then
        echo "Skipping IAM instance profile cleanup because it is managed by Terraform state."
      else
        aws iam remove-role-from-instance-profile \
          --instance-profile-name "$IAM_PROFILE_NAME" \
          --role-name "$IAM_ROLE_NAME" \
          >/dev/null 2>&1 || true

        aws iam delete-instance-profile \
          --instance-profile-name "$IAM_PROFILE_NAME" \
          >/dev/null 2>&1 || true
      fi

      if state_has 'aws_iam_role_policy.aap_secrets_read'; then
        echo "Skipping AAP secrets-read policy cleanup because it is managed by Terraform state."
      else
        aws iam delete-role-policy \
          --role-name "$IAM_ROLE_NAME" \
          --policy-name "${var.environment_name}-aap-secrets-read" \
          >/dev/null 2>&1 || true
      fi

      if state_has 'aws_iam_role_policy.aap_s3_read'; then
        echo "Skipping AAP S3-read policy cleanup because it is managed by Terraform state."
      else
        aws iam delete-role-policy \
          --role-name "$IAM_ROLE_NAME" \
          --policy-name "${var.environment_name}-aap-s3-read" \
          >/dev/null 2>&1 || true
      fi

      if state_has 'aws_iam_role.aap'; then
        echo "Skipping AAP IAM role cleanup because it is managed by Terraform state."
      else
        aws iam delete-role \
          --role-name "$IAM_ROLE_NAME" \
          >/dev/null 2>&1 || true
      fi

      echo "Preflight cleanup complete"
    EOT
  }
}

resource "random_password" "generated" {
  for_each = local.generated_secret_names

  length           = 32
  special          = true
  override_special = "_%@"
}

resource "aws_secretsmanager_secret" "generated" {
  for_each = local.generated_secret_names

  depends_on = [
    terraform_data.preflight_cleanup
  ]

  name                    = "${var.secret_prefix}/${each.value}"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.secret_prefix}/${each.value}"
    Environment = var.environment_name
  }
}

resource "aws_secretsmanager_secret_version" "generated" {
  for_each = local.generated_secret_names

  secret_id     = aws_secretsmanager_secret.generated[each.key].id
  secret_string = random_password.generated[each.key].result

  depends_on = [
    aws_secretsmanager_secret.generated
  ]
}

resource "aws_secretsmanager_secret" "static" {
  for_each = local.static_secret_values

  depends_on = [
    terraform_data.preflight_cleanup
  ]

  name                    = "${var.secret_prefix}/${each.key}"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.secret_prefix}/${each.key}"
    Environment = var.environment_name
  }
}

resource "aws_secretsmanager_secret_version" "static" {
  for_each = local.static_secret_values

  secret_id     = aws_secretsmanager_secret.static[each.key].id
  secret_string = each.value

  depends_on = [
    aws_secretsmanager_secret.static
  ]
}

resource "aws_secretsmanager_secret" "redhat" {
  for_each = local.redhat_secret_values

  depends_on = [
    terraform_data.preflight_cleanup
  ]

  name                    = "${var.secret_prefix}/${each.key}"
  recovery_window_in_days = 0

  tags = {
    Name        = "${var.secret_prefix}/${each.key}"
    Environment = var.environment_name
  }
}

resource "aws_secretsmanager_secret_version" "redhat" {
  for_each = local.redhat_secret_values

  secret_id     = aws_secretsmanager_secret.redhat[each.key].id
  secret_string = each.value

  depends_on = [
    aws_secretsmanager_secret.redhat
  ]
}

resource "aws_secretsmanager_secret" "ssh_private_key" {
  depends_on = [
    terraform_data.preflight_cleanup
  ]

  name                    = local.lab_ssh_private_key_secret_name
  recovery_window_in_days = 0

  tags = {
    Name        = local.lab_ssh_private_key_secret_name
    Environment = var.environment_name
  }
}

resource "aws_secretsmanager_secret_version" "ssh_private_key" {
  secret_id     = aws_secretsmanager_secret.ssh_private_key.id
  secret_string = tls_private_key.lab_ssh.private_key_pem

  depends_on = [
    aws_secretsmanager_secret.ssh_private_key
  ]
}

############################################################
# AAP IAM Role For Reading Lab Secrets
############################################################

resource "aws_iam_role" "aap" {
  name = "${var.environment_name}-aap-role"

  depends_on = [
    terraform_data.preflight_cleanup
  ]

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name        = "${var.environment_name}-aap-role"
    Environment = var.environment_name
  }
}

resource "aws_iam_role_policy" "aap_secrets_read" {
  name = "${var.environment_name}-aap-secrets-read"
  role = aws_iam_role.aap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ]
      Resource = "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:${var.secret_prefix}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "aap" {
  name = "${var.environment_name}-aap-instance-profile"
  role = aws_iam_role.aap.name

  depends_on = [
    aws_iam_role.aap
  ]
}

resource "aws_iam_role_policy" "aap_s3_read" {
  name = "${var.environment_name}-aap-s3-read"
  role = aws_iam_role.aap.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAAPInstallerBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "arn:aws:s3:::aap-containerized-installers/2.7/ansible-automation-platform-containerized-setup-bundle-2.7-1.2-x86_64.tar.gz",
          "arn:aws:s3:::aap-containerized-installers/2.7/manifest_AAP.zip"
        ]
      }
    ]
  })
}

############################################################
# Networking
############################################################

resource "aws_vpc" "lab" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.environment_name}-vpc"
    Environment = var.environment_name
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id

  tags = {
    Name        = "${var.environment_name}-igw"
    Environment = var.environment_name
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment_name}-public-subnet-a"
    Environment = var.environment_name
  }
}

resource "aws_subnet" "resolver" {
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = var.resolver_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment_name}-resolver-subnet-b"
    Environment = var.environment_name
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }

  tags = {
    Name        = "${var.environment_name}-public-rt"
    Environment = var.environment_name
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "resolver" {
  subnet_id      = aws_subnet.resolver.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "lab" {
  name        = "${var.environment_name}-sg"
  description = "Security group for RHEL image mode lab nodes"
  vpc_id      = aws_vpc.lab.id

  ingress {
    description = "SSH from home network and internal VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"

    cidr_blocks = [
      var.ssh_allowed_cidr,
      var.vpc_cidr
    ]
  }

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Internal lab traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Outbound internet access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.environment_name}-sg"
    Environment = var.environment_name
  }
}


############################################################
# Image Builder Security Group
############################################################

resource "aws_security_group" "image_builder" {

  name        = "${var.environment_name}-image-builder-sg"
  description = "Additional access for Image Builder hosts"
  vpc_id      = aws_vpc.lab.id

  ingress {

    description = "Cockpit Web Console"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  ingress {
    description      = "Cockpit Web Console IPv6"
    from_port        = 9090
    to_port          = 9090
    protocol         = "tcp"
    ipv6_cidr_blocks = ["::/0"]

  }

  tags = {

    Name        = "${var.environment_name}-image-builder-sg"
    Environment = var.environment_name
  }
}

############################################################
# EC2 Instances
############################################################

resource "aws_instance" "server" {
  for_each = local.flattened_servers
  ami           = local.selected_ami
  instance_type = each.value.instance_type
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = concat(

    [

      aws_security_group.lab.id

    ],

    each.value.role == "image-builder" ? [

      aws_security_group.image_builder.id

    ] : []

  )

  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = false
  iam_instance_profile = each.value.role == "aap" ? aws_iam_instance_profile.aap.name : null

  root_block_device {

    volume_size = each.value.root_volume
    volume_type = "gp3"
    encrypted   = true

  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname ${each.value.hostname}
    echo "preserve_hostname: true" > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg

  EOF

  tags = {

    Name        = each.value.hostname
    Role        = each.value.role
    Environment = var.environment_name

  }

  depends_on = [

    terraform_data.validate_dns_discovery,
    terraform_data.validate_idm_server,
    aws_key_pair.lab,
    local_sensitive_file.lab_ssh_private_key,
    aws_iam_instance_profile.aap,
    aws_security_group.image_builder,
    aws_secretsmanager_secret_version.ssh_private_key,
    aws_secretsmanager_secret_version.generated,
    aws_secretsmanager_secret_version.static,
    aws_secretsmanager_secret_version.redhat

  ]
}

locals {

  primary_idm_private_ip = try(
    aws_instance.server[local.primary_idm_key].private_ip,
    null

  )
}

resource "aws_ebs_volume" "extra" {

  for_each = {

    for name, server in local.flattened_servers :
    name => server
    if server.extra_volume > 0

  }

  availability_zone = aws_subnet.public.availability_zone
  size              = each.value.extra_volume
  type              = "gp3"
  encrypted         = true
  tags = {

    Name        = "${each.value.hostname}-data"
    Role        = each.value.role
    Environment = var.environment_name
  }

}

resource "aws_volume_attachment" "extra" {

  for_each = aws_ebs_volume.extra
  device_name = "/dev/sdf"
  volume_id   = each.value.id
  instance_id = aws_instance.server[each.key].id

}

resource "aws_eip" "server" {

  for_each = aws_instance.server
  domain = "vpc"
  tags = {

    Name        = "${each.value.tags.Name}-eip"
    Environment = var.environment_name

  }

}

resource "aws_eip_association" "server" {

  for_each = aws_instance.server
  instance_id   = each.value.id
  allocation_id = aws_eip.server[each.key].id

}

############################################################
# Public DNS Records
############################################################

resource "aws_route53_record" "public_dns" {
  for_each = var.create_public_dns_records ? local.flattened_servers : {}

  zone_id = local.public_route53_zone_id
  name    = each.value.hostname
  type    = "A"

  ttl             = 300
  allow_overwrite = true
  records         = [aws_eip.server[each.key].public_ip]

  depends_on = [
    aws_eip_association.server,
    terraform_data.validate_dns_discovery
  ]
}

############################################################
# Route53 Resolver Forwarding To IdM DNS
############################################################

resource "aws_route53_resolver_endpoint" "outbound" {
  name      = "${var.environment_name}-idm-outbound-resolver"
  direction = "OUTBOUND"

  security_group_ids = [
    aws_security_group.lab.id
  ]

  ip_address {
    subnet_id = aws_subnet.public.id
  }

  ip_address {
    subnet_id = aws_subnet.resolver.id
  }

  tags = {
    Name        = "${var.environment_name}-idm-outbound-resolver"
    Environment = var.environment_name
  }
}

resource "aws_route53_resolver_rule" "idm_forward" {
  domain_name          = local.idm_domain_name
  name                 = "${var.environment_name}-idm-forward-rule"
  rule_type            = "FORWARD"
  resolver_endpoint_id = aws_route53_resolver_endpoint.outbound.id

  target_ip {
    ip = local.primary_idm_private_ip
  }

  tags = {
    Name        = "${var.environment_name}-idm-forward-rule"
    Environment = var.environment_name
  }

  depends_on = [
    aws_instance.server,
    terraform_data.validate_idm_server
  ]
}

resource "aws_route53_resolver_rule_association" "idm_forward" {
  resolver_rule_id = aws_route53_resolver_rule.idm_forward.id
  vpc_id           = aws_vpc.lab.id
  name             = "${var.environment_name}-idm-forward-association"
}

############################################################
# Generate Ansible Inventory File
############################################################

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/inventory.ini"

  content = templatefile("${path.module}/inventory.tpl", {
    aws_dns_resolver             = local.aws_dns_resolver
    ansible_ssh_private_key_file = local.ansible_ssh_private_key_file

    aws_region    = var.aws_region
    aws_profile   = var.aws_profile
    secret_prefix = var.secret_prefix

    lab_ssh_private_key_secret_name = local.lab_ssh_private_key_secret_name

    lab_users = var.lab_users
    idm_users = var.idm_users

    parent_domain_name = local.parent_domain_name
    idm_domain_name    = local.idm_domain_name
    idm_realm_name     = local.idm_realm_name
    idm_server_fqdn    = local.primary_idm_hostname
    idm_server_ip      = local.primary_idm_private_ip

    servers = {
      for name, instance in aws_instance.server :
      name => {
        hostname   = instance.tags.Name
        fqdn       = local.flattened_servers[name].hostname
        role       = instance.tags.Role
        private_ip = instance.private_ip
        public_ip  = aws_eip.server[name].public_ip
      }
    }
  })

  depends_on = [
    aws_eip_association.server,
    aws_route53_record.public_dns,
    aws_route53_resolver_rule_association.idm_forward,
    terraform_data.validate_dns_discovery,
    terraform_data.validate_idm_server,
    local_sensitive_file.lab_ssh_private_key,
    aws_secretsmanager_secret_version.ssh_private_key,
    aws_secretsmanager_secret_version.generated,
    aws_secretsmanager_secret_version.static,
    aws_secretsmanager_secret_version.redhat
  ]
}

############################################################
# Clone Repo And Bootstrap Lab
############################################################

resource "terraform_data" "bootstrap_lab" {
  depends_on = [
    local_file.ansible_inventory
  ]

  triggers_replace = [
    local_file.ansible_inventory.content_sha256
  ]

  provisioner "local-exec" {
    working_dir = path.module

    command = <<-EOT
      set -euo pipefail

      REPO_DIR="${abspath(path.module)}/image-mode-hackathon"
      INVENTORY_FILE="${abspath(path.module)}/inventory.ini"

      REPO_URL="https://github.com/claudiol/image-mode-hackathon.git"
      BRANCH="tune-image-builder-server"

      echo "Using inventory: $INVENTORY_FILE"

      chmod 600 "${local.ansible_ssh_private_key_file}"

      if [ ! -d "$REPO_DIR/.git" ]; then
        git clone "$REPO_URL" "$REPO_DIR"
      fi

      cd "$REPO_DIR"

      git fetch origin
      git checkout "$BRANCH"
      git pull --ff-only origin "$BRANCH"

      mkdir -p playbooks/inventory
      cp "$INVENTORY_FILE" playbooks/inventory/hosts

      echo "Generated Ansible inventory:"
      cat playbooks/inventory/hosts

      echo "======================================"
      echo " Deploying Image Mode Lab Services"
      echo "======================================"

      ansible-playbook \
        -i playbooks/inventory/hosts \
        playbooks/deploy-services.yml
    EOT
  }
}