# AAP 2.7 Containerized Installation on AWS EC2

This Ansible playbook automates the deployment of Red Hat Ansible Automation Platform 2.7 Containerized on an AWS EC2 instance. It prepares the RHEL host, registers the system with Red Hat Subscription Management, enables the required AAP repositories, configures hostname and local name resolution, installs required packages, downloads the AAP 2.7 containerized installer bundle, updates the installer inventory, and runs the installer as a non-root `ec2-user`.

---

## 1. Architectural Highlights & Automated Operations

The playbook performs a complete single-node AAP 2.7 containerized installation workflow for AWS-hosted RHEL systems.

* **Red Hat Subscription Management Preparation:** Removes AWS RHUI client packages and forces `subscription-manager` to manage repositories directly.
* **Activation Key Registration:** Registers the EC2 instance to Red Hat using an organization ID and activation key stored securely in Ansible Vault.
* **AAP Repository Enablement:** Enables the required Ansible Automation Platform 2.7 repository for RHEL 10.
* **Persistent Hostname Configuration:** Sets the target AAP FQDN and configures `cloud-init` to preserve the hostname across reboots.
* **IPv4-Only Local Resolution:** Pins the AAP FQDN to the EC2 private IPv4 address in `/etc/hosts`.
* **Installer Inventory Automation:** Copies a base AAP containerized installer inventory and dynamically injects runtime values.
* **Non-Root Installer Execution:** Runs the AAP containerized installer as `ec2-user` to satisfy installer preflight checks.
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
│   ├── inventory
│   └── vars-aap-vault.yml
└── install-aap-2.7-containerized.yml
```

---

## 4. Target Ansible Inventory

Example `inventory/hosts`:

```ini
[aap_controllers]
3.129.25.57 ansible_user=ec2-user ansible_ssh_private_key_file=/path/to/key.pem
```

The outer playbook connects as `ec2-user` and uses privilege escalation with `become: true`.

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

Use standard straight quotes only. Avoid smart quotes.

---

## 6. Base AAP Installer Inventory

The playbook expects a base installer inventory at:

```text
files/inventory
```

This file should come from the extracted AAP containerized installer bundle or a known-good template.

The playbook automatically replaces:

```text
aap.example.com
```

with:

```text
aap.demo.lab.com
```

It also injects runtime values such as:

```ini
ansible_host=<EC2 private IPv4>
routable_hostname=<EC2 private IPv4>
ansible_user=ec2-user
ansible_user_uid=<numeric UID>
ansible_user_dir=/home/ec2-user
ansible_become=true
automationgateway_main_url=https://aap.demo.lab.com
```

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
| **PHASE 7** | Copies and updates the AAP installer inventory. |
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

If Terraform launches the playbook through `local-exec`, the command should look similar to:

```bash
ansible-playbook -i inventory/hosts install-aap-2.7-containerized.yml --vault-password-file vault-password-file
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

Check the last 100 lines:

```bash
sudo tail -n 100 /home/ec2-user/aap-containerized-installer.log
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

The playbook forces the installer to run as:

```text
ec2-user
```

and injects a numeric user ID:

```ini
ansible_user_uid=1000
```

or whatever UID is discovered dynamically from:

```bash
id -u ec2-user
```

### IPv4-Only Internal Connection

AWS hosts may expose IPv6 link-local addresses such as:

```text
fe80::...
```

The playbook prevents the installer from preferring link-local IPv6 by injecting:

```ini
ansible_host=<EC2 private IPv4>
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

### `gateway_admin_username is undefined`

Fix the vault file by adding:

```yaml
gateway_admin_username: "admin"
```

### `the remote user should be a non root user`

Ensure the generated installer inventory contains:

```ini
ansible_user=ec2-user
ansible_user_uid=<numeric UID>
ansible_become=true
```

### Terraform Appears Stuck After Installer Completes

Avoid using `tee` in the installer task. The playbook redirects output directly to:

```text
/home/ec2-user/aap-containerized-installer.log
```

### IPv6 Link-Local Address Appears in Installer Output

Ensure the inventory contains:

```ini
ansible_host=<EC2 private IPv4>
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
