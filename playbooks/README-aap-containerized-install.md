# AAP 2.7 Containerized Installation on AWS EC2

This Ansible playbook automates the deployment of Red Hat Ansible Automation Platform 2.7 Containerized on an AWS EC2 instance. It prepares the RHEL host, registers the system with Red Hat Subscription Management, enables the required AAP repositories, configures hostname and local name resolution, installs required packages, downloads the AAP 2.7 containerized installer bundle, generates a clean AAP installer inventory, and runs the installer as the non-root `ec2-user`.

---

## 1. Architectural Highlights & Automated Operations

The playbook performs a complete single-node AAP 2.7 containerized installation workflow for AWS-hosted RHEL systems.

* **Red Hat Subscription Management Preparation:** Removes AWS RHUI client packages and forces `subscription-manager` to manage repositories directly.
* **Activation Key Registration:** Registers the EC2 instance to Red Hat using an organization ID and activation key stored securely in Ansible Vault.
* **AAP Repository Enablement:** Enables the required Ansible Automation Platform 2.7 repository for RHEL 10.
* **Persistent Hostname Configuration:** Sets the target AAP FQDN and configures `cloud-init` to preserve the hostname across reboots.
* **IPv4-Only Local Resolution:** Pins the AAP FQDN to the EC2 private IPv4 address in `/etc/hosts`.
* **Clean Installer Inventory Generation:** Generates the AAP containerized installer inventory from scratch instead of patching a copied template.
* **Non-Root Installer Execution:** Runs the AAP containerized installer as `ec2-user` to satisfy installer preflight checks.
* **Local Installer Connection:** Uses `ansible_connection=local` in the generated nested installer inventory because the installer is executed directly on the EC2 host.
* **No Global Installer Become:** Avoids setting `ansible_become=true` globally in the nested AAP installer inventory, which can cause the installer preflight check to detect UID `0`.
* **Installer Logging:** Saves the AAP installer output to `/home/ec2-user/aap-containerized-installer.log`.
* **Post-Install Validation:** Waits for the AAP Gateway API endpoint to respond before declaring the installation complete.

---

## 2. Prerequisites & Sizing Requirements

### Target Instance Baseline

* **Operating System:** Red Hat Enterprise Linux 10
* **Instance Type:** `m6i.large`, `m6a.large`, or larger recommended
* **CPU:** 2 vCPUs minimum
* **Memory:** 8 GiB RAM minimum
* **Storage:** 50+ GiB EBS volume recommended
* **User:** `ec2-user` must exist and have sudo privileges
* **Network:** EC2 instance must have outbound access to Red Hat CDN and the installer bundle location

### AWS Security Group Requirements

Allow inbound access to the required AAP service ports from trusted administrative networks:

* **TCP:** `22`, `80`, `443`
* **Optional/Internal TCP:** `5432`, `6379`, `27199`

For a single-node lab install, restrict access to trusted IP ranges where possible.

---

## 3. Directory & File Structure

Recommended project structure:

```text
.
├── inventory/
│   └── hosts
├── files/
│   └── vars-aap-vault.yml
└── install-aap-2.7-containerized.yml
```

A static `files/inventory` template is no longer required. The playbook generates the AAP installer inventory directly inside the extracted installer directory.

---

## 4. Target Ansible Inventory

Example outer Ansible inventory at `inventory/hosts`:

```ini
[aap_controllers]
3.129.25.57 ansible_user=ec2-user ansible_ssh_private_key_file=/path/to/key.pem
```

The outer playbook connects to the EC2 instance as `ec2-user` and uses privilege escalation with `become: true` for host preparation tasks.

When launched by Terraform, make sure Terraform does not run the outer playbook with `sudo ansible-playbook`. The nested installer itself is explicitly run as `ec2-user` by the playbook.

---

## 5. Encrypted Vault File

Create the vault file:

```bash
ansible-vault create files/vars-aap-vault.yml
```

Expected vault variables:

```yaml
---
postgresql_admin_username: "postgres"
postgresql_admin_password: "CHANGEME"

registry_username: "registry-user"
registry_password: "registry-password"

gateway_admin_username: "admin"
gateway_admin_password: "CHANGEME"
gateway_pg_password: "CHANGEME"

controller_admin_password: "CHANGEME"
controller_pg_password: "CHANGEME"

hub_admin_password: "CHANGEME"
hub_pg_password: "CHANGEME"

eda_admin_password: "CHANGEME"
eda_pg_password: "CHANGEME"

automationmetrics_pg_password: "CHANGEME"
automationmetrics_controller_read_pg_password: "CHANGEME"

aap_org_id: "123456"
aap_activation_key: "your-activation-key"
```

Use standard straight quotes only. Avoid smart quotes such as `“` or `”`.

You do not need to place `ansible_user_uid` in the vault. The playbook discovers the UID dynamically with:

```bash
id -u ec2-user
```

---

## 6. Generated AAP Installer Inventory

The playbook generates the AAP containerized installer inventory at:

```text
/opt/ansible-automation-platform-containerized-setup-bundle-2.7-1.2-x86_64/inventory
```

The inventory is generated from scratch to avoid stale or conflicting values such as:

```ini
ansible_user_uid=ec2-user
ansible_become=true
```

Those values are incorrect for this workflow.

Example generated inventory shape:

```ini
[automationgateway]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[automationcontroller]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[automationhub]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[automationeda]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[database]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[redis]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[automationmetrics]
aap.demo.lab.com ansible_connection=local ansible_user=ec2-user ansible_user_uid=1000 ansible_user_dir=/home/ec2-user

[all:vars]
redis_mode=standalone
routable_hostname=172.31.x.x

automationgateway_main_url=https://aap.demo.lab.com
gateway_hostname=aap.demo.lab.com

gateway_pg_host=aap.demo.lab.com
controller_pg_host=aap.demo.lab.com
hub_pg_host=aap.demo.lab.com
eda_pg_host=aap.demo.lab.com

automationmetrics_pg_host=aap.demo.lab.com
automationmetrics_controller_read_pg_host=aap.demo.lab.com
```

Important points:

* `ansible_user_uid` must be numeric, for example `1000`.
* `ansible_connection=local` is expected because the installer is executed on the EC2 host itself.
* Do not set global `ansible_become=true` in the nested AAP installer inventory.
* The outer playbook may still use `become: true` for host preparation.

---

## 7. Playbook Orchestration Summary

| Phase | Automated Task |
| --- | --- |
| **PHASE 0** | Removes AWS RHUI packages and prepares RHSM repo management. |
| **PHASE 1** | Registers the host with Red Hat and enables AAP 2.7 repositories. |
| **PHASE 2** | Sets persistent AAP hostname and configures `cloud-init`. |
| **PHASE 3** | Configures IPv4-only `/etc/hosts` resolution for the AAP FQDN. |
| **PHASE 4** | Installs required packages such as `ansible-core`, `podman`, and `firewalld`. |
| **PHASE 5** | Starts firewalld and opens required service ports. |
| **PHASE 6** | Downloads and extracts the AAP 2.7 containerized installer bundle. |
| **PHASE 7** | Generates a clean AAP installer inventory and validates its resolved variables. |
| **PHASE 8** | Runs the AAP installer as `ec2-user` and records the return code. |
| **PHASE 9** | Validates AAP Gateway availability and prints access details. |

---

## 8. Execution Runbook

### Step 1: Validate SSH Connectivity

```bash
ansible all -i inventory/hosts -m ping
```

Expected result:

```text
SUCCESS => pong
```

### Step 2: Run the AAP Install Playbook

```bash
ansible-playbook -i inventory/hosts install-aap-2.7-containerized.yml --ask-vault-pass
```

### Step 3: Terraform Local-Exec Usage

If Terraform launches the playbook through `local-exec`, use a vault password file instead of an interactive prompt:

```bash
ansible-playbook -i inventory/hosts install-aap-2.7-containerized.yml --vault-password-file files/.vault-pass
```

Avoid:

```bash
sudo ansible-playbook -i inventory/hosts install-aap-2.7-containerized.yml --vault-password-file files/.vault-pass
```

Avoid interactive `--ask-vault-pass` when Terraform is running unattended.

---

## 9. Installer Log and Troubleshooting

The nested AAP installer output is written to:

```text
/home/ec2-user/aap-containerized-installer.log
```

The installer return code is written to:

```text
/home/ec2-user/aap-containerized-installer.rc
```

The generated installer inventory check is written to:

```text
/home/ec2-user/aap-generated-inventory-check.json
```

The user identity used to launch the installer is written to:

```text
/home/ec2-user/aap-installer-whoami.txt
```

Check the last 100 lines:

```bash
sudo tail -n 100 /home/ec2-user/aap-containerized-installer.log
```

Check the generated inventory values:

```bash
cat /home/ec2-user/aap-generated-inventory-check.json | grep -E 'ansible_user|ansible_user_uid|ansible_connection|ansible_host'
```

Expected values:

```text
"ansible_connection": "local"
"ansible_user": "ec2-user"
"ansible_user_uid": 1000
```

Check which user launched the installer:

```bash
cat /home/ec2-user/aap-installer-whoami.txt
```

Expected user:

```text
ec2-user
```

Check whether containers are running:

```bash
sudo podman ps
```

Check the gateway status endpoint:

```bash
curl -k https://aap.demo.lab.com/api/gateway/v1/status/
```

---

## 10. Important Design Notes

### Non-Root Installer Requirement

The AAP containerized installer fails preflight checks if the target user is root.

The playbook runs the nested installer command as:

```text
ec2-user
```

and injects a numeric user ID into each host line of the generated installer inventory:

```ini
ansible_user_uid=1000
```

or whatever UID is discovered dynamically from:

```bash
id -u ec2-user
```

Do not use:

```ini
ansible_user_uid=ec2-user
```

That is invalid because `ansible_user_uid` must be numeric.

### Local Installer Execution

Because the nested AAP installer is run directly on the EC2 host, the generated installer inventory uses:

```ini
ansible_connection=local
```

This is expected.

The important requirement is that the installer process itself is launched as `ec2-user`, not root.

### Avoid Global Become in the Nested Installer Inventory

Do not set this globally in the generated AAP installer inventory:

```ini
ansible_become=true
```

Setting global become can cause the AAP installer preflight role to gather the regular user as root and fail with:

```text
the remote user should be a non root user
```

The outer playbook can still use:

```yaml
become: true
```

for package installation, firewall configuration, RHSM registration, and host configuration.

### IPv4-Only Internal Identity

AWS hosts may expose IPv6 link-local addresses such as:

```text
fe80::...
```

The playbook pins the AAP FQDN to the EC2 private IPv4 address in `/etc/hosts` and sets:

```ini
routable_hostname=<EC2 private IPv4>
```

The public AAP URL remains the FQDN:

```text
https://aap.demo.lab.com
```

---

## 11. Post-Install Access

After installation, access AAP Gateway at:

```text
https://aap.demo.lab.com
```

Default admin username is defined by:

```yaml
gateway_admin_username
```

The password is defined by:

```yaml
gateway_admin_password
```

Both values are stored in:

```text
files/vars-aap-vault.yml
```

---

## 12. Idempotency Behavior

The playbook checks whether the AAP Gateway status endpoint is already responding before rerunning the installer.

If the endpoint returns one of the following statuses, the installer is skipped:

```text
200
401
403
```

This prevents unnecessary reinstall attempts after AAP is already running.

---

## 13. Common Failure Points

### `aap_activation_key is undefined`

Confirm the vault file is being loaded and contains:

```yaml
aap_activation_key: "your-activation-key"
aap_org_id: "123456"
```

If the vault is under `files/`, prefer loading it with:

```yaml
include_vars:
  file: "{{ playbook_dir }}/files/vars-aap-vault.yml"
```

### `gateway_admin_username is undefined`

Fix the vault file by adding:

```yaml
gateway_admin_username: "admin"
```

### `the remote user should be a non root user`

Verify all of the following:

```bash
cat /home/ec2-user/aap-installer-whoami.txt
cat /home/ec2-user/aap-generated-inventory-check.json | grep -E 'ansible_user|ansible_user_uid|ansible_connection'
```

Expected values:

```text
ec2-user
"ansible_connection": "local"
"ansible_user": "ec2-user"
"ansible_user_uid": 1000
```

Also confirm the generated installer inventory does not contain:

```ini
ansible_user_uid=ec2-user
ansible_become=true
```

### Terraform Appears Stuck After Installer Completes

Avoid using `tee` in the installer task. The playbook redirects output directly to:

```text
/home/ec2-user/aap-containerized-installer.log
```

### IPv6 Link-Local Address Appears in Installer Output

Ensure `/etc/hosts` maps the AAP FQDN to the EC2 private IPv4 address:

```text
172.31.x.x aap.demo.lab.com aap
```

Also ensure the generated inventory contains:

```ini
routable_hostname=<EC2 private IPv4>
```

---

## 14. Verification Commands

Run these from the EC2 instance after installation:

```bash
sudo podman ps
```

```bash
curl -k https://aap.demo.lab.com/api/gateway/v1/status/
```

```bash
sudo firewall-cmd --list-ports
```

```bash
hostname -f
```

Expected hostname:

```text
aap.demo.lab.com
```
