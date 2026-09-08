---
###############################################################################
# Red Hat Container Registry authentication
###############################################################################

redhat_registry_url: registry.redhat.io

redhat_registry_username: >-
  {{
    lookup('env', 'REDHAT_REGISTRY_USERNAME') | default('', true)
  }}

redhat_registry_password: >-
  {{
    lookup('env', 'REDHAT_REGISTRY_PASSWORD') | default('', true)
  }}

###############################################################################
# AAP Controller connection
###############################################################################

aap2_controller_url: >-
  {{
    lookup('env', 'AAP2_CONTROLLER_URL') | default('', true)
  }}

aap2_controller_username: >-
  {{
    lookup('env', 'AAP2_CONTROLLER_USERNAME') | default('', true)
  }}

aap2_controller_password: >-
  {{
    lookup('env', 'AAP2_CONTROLLER_PASSWORD') | default('', true)
  }}

aap2_organization: "Default"

###############################################################################
# Variables expected by infra.aap_configuration
###############################################################################

aap_hostname: >-
  {{
    aap2_controller_url
  }}

aap_username: >-
  {{
    aap2_controller_username
  }}

aap_password: >-
  {{
    aap2_controller_password
  }}

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
    lookup('env', 'AUTOMATION_HUB_TOKEN') | default('', true)
  }}

###############################################################################
# CoP AAP project source
###############################################################################

configure_git_credentials: false

git_username: ""

git_password: ""

git_ssh_key: ""

git_ssh_key_passphrase: ""

git_repository: "https://gitlab.com/philip860/rhel-image-mode-aap.git"

git_repository_branch: "dev"

###############################################################################
# Dynamically provisioned GitLab and sample pipeline source
###############################################################################

# Terraform writes gitlab_hostname on the host in the generated gitlab group.
gitlab_hostname: >-
  {{
    hostvars[groups['gitlab'][0]].gitlab_hostname
    | default(groups['gitlab'][0], true)
  }}

gitlab_url: >-
  {{
    'https://' ~ gitlab_hostname
  }}

sample_git_project_path: >-
  {{
    lookup('env', 'SAMPLE_GIT_PROJECT_PATH')
    | default('image-mode/sample-rhel9-web.git', true)
  }}

# Complete, environment-specific repository URL containing the Containerfile.
sample_git_repository_url: >-
  {{
    gitlab_url ~ '/' ~ sample_git_project_path
  }}

###############################################################################
# Dynamically provisioned Quay registry and sample image destination
###############################################################################

quay_hostname: >-
  {{
    hostvars[groups['quay'][0]].quay_hostname
    | default(groups['quay'][0], true)
  }}

sample_quay_repository_path: >-
  {{
    lookup('env', 'SAMPLE_QUAY_REPOSITORY_PATH')
    | default('image-mode/sample-rhel9', true)
  }}

# Complete, environment-specific Quay repository name without a tag.
sample_quay_image: >-
  {{
    quay_hostname ~ '/' ~ sample_quay_repository_path
  }}

sample_image_tag: >-
  {{
    lookup('env', 'SAMPLE_IMAGE_TAG') | default('v1', true)
  }}

###############################################################################
# Dynamically provisioned image-builder server
###############################################################################

# automation.tf overrides this for every selected image builder.
server_hostname: >-
  {{
    hostvars[groups['image_builder'][0]].private_ip
    | default(hostvars[groups['image_builder'][0]].ansible_host, true)
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
# Dynamically provisioned Quay registry credentials
###############################################################################

custom_registry_url: >-
  {{
    quay_hostname
  }}
