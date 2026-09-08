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
  }}
# Complete, environment-specific Quay repository name without a tag.
sample_quay_image: >-
  {{
    quay_hostname ~ '/' ~ sample_quay_repository_path
  }}
sample_image_tag: >-
  {{
    lookup('env', 'SAMPLE_IMAGE_TAG')
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
custom_registry_username: >-
  {{
    lookup('env', 'QUAY_USERNAME')
  }}
custom_registry_password: >-
  {{
    lookup('env', 'QUAY_PASSWORD')
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
