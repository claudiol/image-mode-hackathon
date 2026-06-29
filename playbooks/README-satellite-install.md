---

# 📖 Red Hat Satellite 6.19.1 Offline Installation Guide

This deployment runbook details how to execute an unattended, disconnected installation of **Red Hat Satellite 6.19.1** on a target RHEL 9 virtual instance hosted within an isolated AWS VPC subnet.

## ⚠️ CRITICAL PRE-REQUISITE: Manual ISO Download

Because the Red Hat Customer Portal strictly protects multi-gigabyte product image binaries behind organization-scoped access control tokens and dynamic edge-proxy redirects, **automated API downloads via tools like `wget` or `get_url` are blocked and will fail with 404/403 errors.**

Before running this automation, you must perform the following manual steps:

1. Open your web browser on your local workstation and log into the **[Red Hat Customer Portal](https://access.redhat.com/)**.
2. Navigate to **Downloads > Red Hat Satellite > Version 6.19.1** and download the official installation DVD: **`Satellite-6.19.1-rhel-9-x86_64.dvd.iso`**.
3. Stage this downloaded ISO on your Ansible control node in the **same directory** as the playbook file below.

---

## 📜 Complete Ansible Playbook: `deploy-satellite.yml`

This playbook implements the localized staging strategy, establishes clean loopback mount maps inside the writable storage tier, constructs an offline repository map, and drives the unattended installer script to completion.

```yaml
---
- name: Install Disconnected Red Hat Satellite 6.19.1 via Local ISO Staging
  hosts: satellite
  become: true

  vars:
    # -------------------------------------------------------------------------
    # Network Architecture Settings (Aligned with Hackathon DNS Requirements)
    # -------------------------------------------------------------------------
    satellite_ip: "10.20.1.154"
    satellite_fqdn: "satellite.redhat.local"
    satellite_shortname: "satellite"
    
    initial_admin_username: "admin"
    initial_admin_password: "Changeme123!"
    organization_name: "Hackathon_Org"
    location_name: "AWS_West_Region"
    
    # -------------------------------------------------------------------------
    # Filesystem & Storage Path Settings (Targeting Writable /var Tier)
    # -------------------------------------------------------------------------
    satellite_iso_src: "Satellite-6.19.1-rhel-9-x86_64.dvd.iso" # Must be staged locally
    satellite_iso_dest: "/var/tmp/Satellite-6.19.1-rhel-9-x86_64.dvd.iso"
    satellite_mount_path: "/var/mnt/satellite_iso"

  tasks:
    - name: 1. Ensure hostname matches the explicit Hackathon FQDN
      ansible.builtin.hostname:
        name: "{{ satellite_fqdn }}"

    - name: 2. Configure /etc/hosts with absolute IP-to-FQDN reverse mapping
      ansible.builtin.blockinfile:
        path: /etc/hosts
        block: |
          {{ satellite_ip }} {{ satellite_fqdn }} {{ satellite_shortname }}
          127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
        marker: "# {mark} ANSIBLE MANAGED HOSTS CONFIG"

    - name: 3. Stream the manually staged ISO from control machine to target instance
      ansible.builtin.copy:
        src: "{{ satellite_iso_src }}"
        dest: "{{ satellite_iso_dest }}"
        mode: '0644'

    - name: 4. Safety Check - Ensure any stale read-only mount is completely unhooked
      ansible.posix.mount:
        path: "{{ satellite_mount_path }}"
        state: unmounted

    - name: 5. Ensure mount point directory exists within the writable storage boundary
      ansible.builtin.file:
        path: "{{ satellite_mount_path }}"
        state: directory
        mode: '0755'

    - name: 6. Mount the Satellite 6.19.1 ISO via kernel loopback device
      ansible.posix.mount:
        path: "{{ satellite_mount_path }}"
        src: "{{ satellite_iso_dest }}"
        fstype: iso9660
        opts: loop,ro
        state: mounted

    - name: 7. Inject offline repository pointing to the mounted ISO repository directory
      ansible.builtin.yum_repository:
        name: "local-satellite-iso-media"
        description: "Satellite 6.19.1 Installer Local ISO Media"
        baseurl: "file://{{ satellite_mount_path }}/Satellite"
        enabled: true
        gpgcheck: false

    - name: 8. Synchronize DNF package storage metadata cache
      ansible.builtin.dnf:
        update_cache: true

    - name: 9. Install core Satellite engine package from the local ISO repository
      ansible.builtin.dnf:
        name: satellite
        state: present

    - name: 10. Run the Unattended Satellite Installer Core via Absolute System Binary Path
      ansible.builtin.command: >
        /usr/sbin/satellite-installer --scenario satellite
        --foreman-initial-admin-username={{ initial_admin_username }}
        --foreman-initial-admin-password={{ initial_admin_password }}
        --certs-node-fqdn={{ satellite_fqdn }}
        --foreman-initial-organization={{ organization_name | quote }}
        --foreman-initial-location={{ location_name | quote }}
      async: 1800      # Installs take roughly 15-25 minutes depending on volume disk speeds
      poll: 30         # Status check updates pushed to terminal logs every 30 seconds
      register: satellite_installer_output

    - name: 11. Print out the deployment finalization connectivity matrix
      ansible.builtin.debug:
        msg: 
          - "🚀 Offline ISO Satellite 6.19.1 Core Engine Completed Successfully!"
          - "Web Interface Target: https://{{ satellite_fqdn }}"
          - "Administrative Username: {{ initial_admin_username }}"
          - "Administrative Password: {{ initial_admin_password }}"

```

---

## 🛠️ Step-by-Step Execution Protocol

### Step 1: Ensure `ansible.posix` is installed on your local control node

Verify your environment includes the collection required to manage loopback mounts:

```bash
ansible-galaxy collection install ansible.posix

```

### Step 2: Validate Filesystem Staging

Run `ls -l` in your deployment directory to verify that the manually downloaded ISO asset sits directly alongside your playbook code:

```bash
$ ls -lh
-rw-r--r--. 1 user group 3.8G deploy-satellite.yml
-rw-r--r--. 1 user group 7.4G Satellite-6.19.1-rhel-9-x86_64.dvd.iso

```

### Step 3: Fire the Automation Run

Kick off the playbook execution path against your target inventory group definition:

```bash
ansible-playbook -i inventory.ini deploy-satellite.yml

```

### Step 4: Access the Console

Once completed, follow the **SSH Tunneling instructions** from the previous configuration runbook to route your browser safely through the public Bastion boundary to the private environment:

* Run your tunnel pointing to the new domain string: `sudo ssh -N -L 443:10.20.1.154:443 ec2-user@18.236.159.51 -i ~/.ssh/aws_bastion_key`
* Map your local client computer's `/etc/hosts` file: `127.0.0.1 satellite.redhat.local`
* Point your browser to: **`https://satellite.redhat.local`**
