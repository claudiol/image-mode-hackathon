---
###############################################################################
# Red Hat Container Registry authentication
###############################################################################

redhat_registry_url: registry.redhat.io

redhat_registry_username: >-
  {{
    lookup('env', 'REDHAT_REGISTRY_USERNAME')
  }}

redhat_registry_password: >-
  {{
    lookup('env', 'REDHAT_REGISTRY_PASSWORD')
  }}

###############################################################################
# AAP Controller connection
###############################################################################

aap2_controller_url: >-
  {{
    lookup('env', 'AAP2_CONTROLLER_URL')
  }}

aap2_controller_username: >-
  {{
    lookup('env', 'AAP2_CONTROLLER_USERNAME')
  }}

aap2_controller_password: >-
  {{
    lookup('env', 'AAP2_CONTROLLER_PASSWORD')
  }}

aap2_organization: "Default"

###############################################################################
# Variables expected by infra.aap_configuration
###############################################################################

aap_hostname: "{{ aap2_controller_url }}"
aap_username: "{{ aap2_controller_username }}"
aap_password: "{{ aap2_controller_password }}"
aap_validate_certs: false

###############################################################################
# Red Hat Automation Hub
###############################################################################

automation_hub_url: >-
  https://console.redhat.com/api/automation-hub/content/published/

automation_hub_auth_url: >-
  https://sso.redhat.com/auth/realms/redhat-external/protocol/openid-connect/token

automation_hub_token: >-
  {{
    lookup('env', 'AUTOMATION_HUB_TOKEN')
  }}

###############################################################################
# CoP project source
###############################################################################

# This is the repository that AAP uses for the CoP playbooks themselves.
git_repository: "https://gitlab.com/philip860/rhel-image-mode-aap.git"
git_repository_branch: "dev"

# Leave this false if the repository above is publicly readable.
configure_git_credentials: false

git_username: ""
git_password: ""
git_ssh_key: ""
git_ssh_key_passphrase: ""

###############################################################################
# Dynamically provisioned GitLab service
###############################################################################

gitlab_hostname: >-
  {{
    hostvars[groups['gitlab'][0]].gitlab_hostname
    | default(groups['gitlab'][0], true)
  }}

gitlab_url: >-
  {{
    'https://' ~ gitlab_hostname
  }}

# GitLab user/group owning the application and SOE repositories.
gitlab_namespace: >-
  {{
    lookup('env', 'GITLAB_NAMESPACE')
  }}

###############################################################################
# Dynamically provisioned image-builder server
###############################################################################

# Terraform overrides this for each builder with --extra-vars. This default is
# retained so the variables file can also be used directly with the inventory.
server_hostname: >-
  {{
    hostvars[groups['image_builder'][0]].private_ip
    | default(
        hostvars[groups['image_builder'][0]].ansible_host,
        true
      )
  }}

server_name: >-
  {{
    groups['image_builder'][0]
  }}

###############################################################################
# SSH credentials inherited from the generated inventory
###############################################################################

server_username: >-
  {{
    hostvars[groups['image_builder'][0]].ansible_user
  }}

server_password: ""

server_ssh_key: >-
  {{
    lookup(
      'file',
      hostvars[groups['image_builder'][0]].ansible_ssh_private_key_file
    )
  }}

server_ssh_key_passphrase: ""

###############################################################################
# Dynamically provisioned Quay registry
###############################################################################

quay_hostname: >-
  {{
    hostvars[groups['quay'][0]].quay_hostname
    | default(groups['quay'][0], true)
  }}

# Registry credentials generally expect a hostname, not an https:// URL.
custom_registry_url: "{{ quay_hostname }}"

custom_registry_username: >-
  {{
    lookup('env', 'QUAY_USERNAME')
  }}

custom_registry_password: >-
  {{
    lookup('env', 'QUAY_PASSWORD')
  }}

# Namespace used when constructing complete container image references.
quay_namespace: >-
  {{
    lookup('env', 'QUAY_NAMESPACE')
    | default(custom_registry_username, true)
  }}

###############################################################################
# AWS credentials used to push AMIs
###############################################################################

aws_access_key: >-
  {{
    lookup('env', 'PIPELINE_AWS_ACCESS_KEY')
  }}

aws_secret_key: >-
  {{
    lookup('env', 'PIPELINE_AWS_SECRET_KEY')
  }}

aws_sts_token: >-
  {{
    lookup('env', 'PIPELINE_AWS_STS_TOKEN')
  }}