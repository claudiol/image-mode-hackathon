# AWS Infrastructure Deployment & Connectivity Runbook

This documentation provides the official asset directory, network layout, and edge routing protocols for the RHEL Image Mode hackathon environment. All core management engines reside within private, isolated VPC subnets and must be accessed exclusively via the public transit gateway (Bastion host).

---

## 📐 Network Architecture & Inventory Asset Directory

The infrastructure separates public entry points from high-state control plane systems. Private hosts utilize the Bastion proxy for administrative control, and exit to the internet via an outbound NAT gateway for external repository syncing.

### Core Server Inventory

| Host Name | Role / Purpose | Private IP | Public IP | Operational Port Access |
| --- | --- | --- | --- | --- |
| **bastion** | Public Transit Gateway & SSH Proxy Jump | `10.20.101.63` | `18.236.159.51` | Inbound SSH (`22`) from External |
| **satellite** | Red Hat Satellite 6.16 Package Repository | `10.20.1.103` | *None (Isolated)* | SSH (`22`), WebUI HTTPS (`443`) |
| **idm** | Identity Management (FreeIPA Core Realm) | `10.20.2.100` | *None (Isolated)* | SSH (`22`), WebUI HTTPS (`443`) |
| **quay** | Red Hat Quay OCI Container Registry | `10.20.3.59` | *None (Isolated)* | SSH (`22`), WebUI HTTPS (`443`) |
| **ansible** | Ansible Automation Platform Execution Node | `10.20.2.68` | *None (Isolated)* | SSH (`22`), WebUI HTTPS (`443`) |

---

## ⚙️ OpenSSH Client Configuration Blueprint

To streamline command-line execution and automate playbooks without passing heavy proxy strings, place this exact configuration block inside your local workstation’s client configuration file.

### File Path: `~/.ssh/config`

```text
# Global Hackathon Defaults
Host *
    ServerAliveInterval 60
    ServerAliveCountMax 5
    StrictHostKeyChecking ask

# Public-Facing Boundary Node
Host bastion
    HostName 18.236.159.51
    User ec2-user
    IdentityFile ~/.ssh/aws_bastion_key

# -------------------------------------------------------
# Private Nodes (Proxy-Jump Routed via Bastion)
# -------------------------------------------------------

Host satellite
    HostName 10.20.1.103
    User ec2-user
    IdentityFile ~/.ssh/aws_bastion_key
    ProxyJump bastion

Host idm
    HostName 10.20.2.100
    User ec2-user
    IdentityFile ~/.ssh/aws_bastion_key
    ProxyJump bastion

Host quay
    HostName 10.20.3.59
    User ec2-user
    IdentityFile ~/.ssh/aws_bastion_key
    ProxyJump bastion

Host ansible
    HostName 10.20.2.68
    User ec2-user
    IdentityFile ~/.ssh/aws_bastion_key
    ProxyJump bastion

```

> **Security Guardrail:** Your local OpenSSH engine will reject this file if permissions are open to other system users. Restrict it immediately by executing:
> ```bash
> chmod 600 ~/.ssh/config
> 
> ```
> 
> 

---

## 🚀 Edge Connectivity & Secure Tunnel Commands

Because these systems are deployed within private enterprise topologies, you cannot access their HTTPS administration dashboards directly. You must run a **Local Port Forwarding SSH Tunnel** to loop the remote private ports down to your local loopback address (`127.0.0.1`).

### 1. Unified Jump Commands (Command Line Terminal Access)

With your `~/.ssh/config` file populated, you can skip writing manual proxy configurations. Terminal access to the private instances is fully transparent:

```bash
ssh satellite
ssh idm
ssh quay
ssh ansible

```

---

### 2. HTTPS WebUI Console Access Tunnels (Port 443 -> Local)

Run these commands in a separate, dedicated terminal window on your local laptop to map the secure web interfaces of the private applications down to your local browser.

#### 🛰️ Connect to Red Hat Satellite Console

```bash
ssh -N -L 8443:10.20.1.103:443 ec2-user@18.236.159.51 -i ~/.ssh/aws_bastion_key

```

* **Local Web Browser URL:** [https://127.0.0.1:8443](https://www.google.com/search?q=https://127.0.0.1:8443)

#### 🆔 Connect to Identity Management (IdM / FreeIPA) Console

```bash
ssh -N -L 7443:10.20.2.100:443 ec2-user@18.236.159.51 -i ~/.ssh/aws_bastion_key

```

* **Local Web Browser URL:** [https://127.0.0.1:7443](https://www.google.com/search?q=https://127.0.0.1:7443)

#### 🐳 Connect to Red Hat Quay Registry Console

```bash
ssh -N -L 6443:10.20.3.59:443 ec2-user@18.236.159.51 -i ~/.ssh/aws_bastion_key

```

* **Local Web Browser URL:** [https://127.0.0.1:6443](https://www.google.com/search?q=https://127.0.0.1:6443)

#### 🤖 Connect to Ansible Automation Platform Console

```bash
ssh -N -L 5443:10.20.2.68:443 ec2-user@18.236.159.51 -i ~/.ssh/aws_bastion_key

```

* **Local Web Browser URL:** [https://127.0.0.1:5443](https://www.google.com/search?q=https://127.0.0.1:5443)

### 💡 Syntax Parameter Breakdown:

* `-N`: Tells OpenSSH to strictly open the routing tunnel and allocate the ports **without executing a remote command console**. This leaves the terminal window open cleanly as a persistent background daemon pipe.
* `-L [Local Port]:[Private Target IP]:[Target Port]`: Standardizes local port definitions so multiple private dashboards can run simultaneously without colliding on your localhost interface.
