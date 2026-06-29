# AWS IdM (FreeIPA) Prerequisites & Installation Automation Playbook

This Ansible playbook automates the deployment of Red Hat Identity Management (IdM / FreeIPA) on an Amazon Web Services (AWS) EC2 instance within an isolated VPC. It automatically resolves virtualization race conditions, configures AWS Red Hat Update Infrastructure (RHUI) links, pins local network name resolution over aggressive DHCP overrides, and completes an unattended cluster initialization.

---

## 1. Architectural Highlights & Automated Operations

The playbook executes a sequence of foundational changes to prepare the host environment for enterprise identity infrastructure:
* **Dynamic Fact Discovery:** Automatically scrapes the active internal AWS private IPv4 address to eliminate hardcoded values.
* **NetworkManager Pinning:** Configures split-horizon DNS routing to ensure local loopback resolution takes primary authority over VPC-level DHCP updates.
* **Systemd Remediation:** Strips the dynamic `myhostname` plugin from Name Service Switch (`nsswitch.conf`) to block link-local IPv6 interception.
* **Dogtag CA Alignment:** Programs kernel execution parameters to bind valid IPv6 loopback boundaries required by the embedded Certificate Authority backend.
* **Security & Vault Isolation:** Encrypts core system directory root secrets away from plaintext execution tracks using Ansible Vault.

---

## 2. Prerequisites & Sizing Requirements

### Target Instance Baseline
* **Operating System:** Red Hat Enterprise Linux (RHEL) 8 or RHEL 9 (Clean Minimal Install)
* **Instance Size:** `t3.large` or `m6i.large` minimum (2 vCPUs, 8 GiB RAM minimum)
* **Storage Allocation:** 50+ GB EBS (`gp3`)

### AWS Security Group Requirements
Ensure your instance's active AWS Security Group permits the following inbound ports from your VPC subnets or administrative endpoints:
* **TCP:** `80`, `443`, `389`, `636`, `88`, `464`, `53`
* **UDP:** `88`, `464`, `53`, `123`

---

## 3. Directory & File Structure

For standard execution, organize your workspace as follows:
```text
.
├── inventory/
│   └── hosts                 # Inventory tracking target nodes
├── vars-vault.yml            # Encrypted Ansible Vault credentials
└── deploy-idm-pre-reqs.yml   # The deployment playbook

```

### 1. Configuration Target Inventory (`inventory/hosts`)

Define the target RHEL node mapping details:

```ini
[idm_servers]
10.20.2.58 ansible_user=ec2-user ansible_ssh_private_key_file=/path/to/key.pem

```

### 2. Encrypted Vault Creation (`vars-vault.yml`)

Generate an encrypted credentials layer using the native Ansible Vault engine to house directory credentials securely:

```bash
ansible-vault create vars-vault.yml

```

Provide a secure vault execution passphrase and format the encrypted file keys exactly as shown below:

```yaml
---
idm_vault_dm_password: "DM_Secret_Pass123"
idm_vault_admin_password: "Admin_Secret_Pass123"

```

---

## 4. Playbook Orchestration Play Summary

| Phase | Automated Blueprint Task |
| --- | --- |
| **PHASE 0** | Decrypts and injects `vars-vault.yml` values in runtime memory. |
| **PHASE 1** | Assures the state and availability of native AWS RHUI tracking packages. |
| **PHASE 2** | Fixes a persistent target FQDN and patches `cloud-init` to preserve the state. |
| **PHASE 3** | Remediates name service lookup switches and overrides local `/etc/hosts`. |
| **PHASE 4** | Actively maps kernel capabilities to enable an active IPv6 loopback route. |
| **PHASE 5** | Drops optimizations for the internal 389 Directory Server engine. |
| **PHASE 6** | Deploys Identity Management Server binaries and DNS extension packages. |
| **PHASE 7** | Pinpoints interface connection tables and opens localized firewall arrays. |
| **PHASE 8** | Runs the inline installation template using discovered runtime arguments. |

---

## 5. Execution Deployment Runbook

### Step 1: Pre-execution Syntax and Connection Validation

Verify connection states and authenticate SSH management mappings before modifying internal node structures:

```bash
ansible idm_servers -i inventory/hosts -m ping

```

### Step 2: Live Blueprint Execution

Trigger the playbook lifecycle. You **must** supply the `--ask-vault-pass` runtime flag so that the runtime engine can query you for the decryption key required to evaluate `vars-vault.yml`:

```bash
ansible-playbook -i inventory/hosts deploy-idm-pre-reqs.yml --ask-vault-pass

```

### Step 3: Idempotency Validation (Optional Second Execution)

Running the playbook a second time will cleanly bypass the installation block thanks to встроен text anchors (`creates: /etc/ipa/default.conf`).

```bash
ansible-playbook -i inventory/hosts deploy-idm-pre-reqs.yml --ask-vault-pass

```

*Expected Clean Event State:* `changed=0` on the server installation task blocks.

---

## 6. Verification & Post-Install Administrative Handshake

Once the playbook completes, log straight into your target server shell to authenticate against the new domain structure:

```bash
# 1. Establish administrative Kerberos tracing down standard out paths
KRB5_TRACE=/dev/stdout kinit admin

# 2. Key in the Admin password established inside your vault file (e.g., Admin_Secret_Pass123)

# 3. Print your verified directory tickets
klist

```

### Expected Successful Output Token Trace:

```text
Ticket cache: KCM:0:11202
Default principal: admin@AWS.REDHAT.LOCAL

Valid starting       Expires              Service principal
06/10/2026 15:40:00  06/11/2026 15:40:00  krbtgt/AWS.REDHAT.LOCAL@AWS.REDHAT.LOCAL
```
