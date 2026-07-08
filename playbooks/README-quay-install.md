# Red Hat Quay Single-Node Containerized Deployment on AWS EC2

This Ansible playbook automates deployment of a single-node Red Hat Quay
registry on a RHEL EC2 instance using Podman containers.

## 1. Architectural Highlights & Automated Operations

The playbook performs:

-   Host package preparation
-   Podman installation
-   Firewalld configuration
-   Red Hat registry authentication
-   Quay pod creation
-   PostgreSQL deployment
-   Redis deployment
-   Local filesystem registry storage
-   Self-signed TLS generation
-   Quay configuration generation
-   PostgreSQL pg_trgm enablement
-   Initial superuser creation
-   Email verification disabling for labs
-   Default organization creation
-   Default team creation for image workflows

## 2. Target Architecture

Containers:

-   quay-registry
-   quay-postgres
-   quay-redis

Storage:

/opt/quay/config /opt/quay/storage /opt/quay/postgres /opt/quay/redis

Published Ports:

-   443 -\> Quay HTTPS
-   8080 -\> Quay HTTP

## 3. Recommended EC2 Sizing

Operating System:

-   Red Hat Enterprise Linux 9

Recommended:

-   4 vCPU
-   16 GiB RAM
-   100+ GiB EBS volume

Minimum Lab:

-   2 vCPU
-   8 GiB RAM
-   50 GiB storage

## 4. Project Structure

. ├── inventory/ │ └── hosts ├── files/ │ └── vars-quay-vault.yml └──
deploy-quay.yml

## 5. Inventory Example

\[quay_demo\] quay-demo.example.com ansible_user=ec2-user
ansible_ssh_private_key_file=/path/key.pem

## 6. Required Vault Variables

Create:

ansible-vault create files/vars-quay-vault.yml

Required content:

``` yaml
---
# Red Hat Registry Authentication

redhat_registry_username: "your-redhat-user"
redhat_registry_password: "your-redhat-password"

# Container Images

quay_image: "registry.redhat.io/quay/quay-rhel8:v3.15"
postgres_image: "registry.redhat.io/rhel9/postgresql-15:latest"
redis_image: "docker.io/library/redis:7"

# Quay Host Settings

quay_hostname: "quay-demo.example.com"

# Database

quay_db_user: "quay"
quay_db_password: "CHANGE_ME"
quay_db_name: "quay"

# Secrets

quay_secret_key: "CHANGE_ME_LONG_RANDOM_SECRET"

# Initial Admin Account

quay_superuser: "quayadmin"
quay_superuser_password: "CHANGE_ME"
quay_superuser_email: "quayadmin@example.com"

# Default Organization

quay_default_org: "image-mode"
quay_default_team: "writers"

# TLS Certificate

quay_tls_cert_days: 3650
quay_tls_country: "US"
quay_tls_state: "MA"
quay_tls_city: "Springfield"
quay_tls_org: "Demo"
quay_tls_org_unit: "Lab"
```

## 7. Deployment Workflow

Phase summary:

PHASE 1 - Install required RPM packages\
PHASE 2 - Authenticate to registry.redhat.io\
PHASE 3 - Create Quay storage directories\
PHASE 4 - Generate TLS certificates\
PHASE 5 - Start PostgreSQL\
PHASE 6 - Enable pg_trgm extension\
PHASE 7 - Start Redis\
PHASE 8 - Generate config.yaml\
PHASE 9 - Start Quay registry\
PHASE 10 - Initialize admin user\
PHASE 11 - Disable email verification requirement\
PHASE 12 - Create default organization/team

## 8. Run Deployment

Validate connectivity:

``` bash
ansible all -i inventory/hosts -m ping
```

Deploy:

``` bash
ansible-playbook \
-i inventory/hosts \
deploy-quay.yml \
--ask-vault-pass
```

Automation example:

``` bash
ansible-playbook \
-i inventory/hosts \
deploy-quay.yml \
--vault-password-file files/.vault-pass
```

## 9. Validation

Check containers:

``` bash
sudo podman ps
```

Expected:

-   quay-registry
-   quay-postgres
-   quay-redis

Check Quay:

``` bash
curl -k https://quay-demo.example.com
```

Login:

``` bash
podman login --tls-verify=false quay-demo.example.com
```

## 10. Push Test Image

Pull UBI:

``` bash
podman pull registry.access.redhat.com/ubi9/ubi
```

Tag:

``` bash
podman tag \
registry.access.redhat.com/ubi9/ubi \
quay-demo.example.com/image-mode/ubi9-test:latest
```

Push:

``` bash
podman push \
--tls-verify=false \
--remove-signatures \
quay-demo.example.com/image-mode/ubi9-test:latest
```

Note:

--remove-signatures is required when mirroring signed Red Hat images
because changing the image destination or layer representation
invalidates upstream signatures.

Images created by your own image-mode build pipeline normally do not
require this option.

## 11. Troubleshooting

### Quay HTTPS unavailable

Check:

``` bash
sudo podman logs quay-registry
```

### pg_trgm missing

Error:

Could not connect to database. You must install pg_trgm extension

Verify:

``` bash
sudo podman exec quay-postgres psql -U quay -d quay -c "\dx"
```

### Push returns 502

Check storage permissions:

``` bash
ls -ld /opt/quay/storage
```

Expected:

-   container writable
-   SELinux container_file_t context

### Invalid Login

Verify initial user exists and email is confirmed:

``` bash
sudo podman exec quay-postgres \
psql -U quay -d quay \
-c "select username,email_confirmed from public.user;"
```

## 12. Post Install URL

Access:

https://quay-demo.example.com

Default user:

quay_superuser

Default organization:

image-mode
