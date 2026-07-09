[all:vars]
ansible_user=ec2-user
ansible_ssh_private_key_file=${ansible_ssh_private_key_file}
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

aws_region=${aws_region}
secret_prefix=${secret_prefix}
aws_profile=${aws_profile}

aws_dns_resolver=${aws_dns_resolver}
lab_ssh_private_key_secret_name=${lab_ssh_private_key_secret_name}

parent_domain_name=${parent_domain_name}
idm_domain_name=${idm_domain_name}
idm_realm_name=${idm_realm_name}
idm_server_fqdn=${idm_server_fqdn}
idm_server_ip=${idm_server_ip}

############################################################
# IdM Users
############################################################

lab_users=${jsonencode(lab_users)}
idm_users=${jsonencode(idm_users)}

[idm]
%{ for name, s in servers ~}
%{ if s.role == "idm" ~}
${s.fqdn} ansible_host=${s.public_ip} private_ip=${s.private_ip}
%{ endif ~}
%{ endfor ~}

[satellite]
%{ for name, s in servers ~}
%{ if s.role == "satellite" ~}
${s.fqdn} ansible_host=${s.public_ip} private_ip=${s.private_ip}
%{ endif ~}
%{ endfor ~}

[aap]
%{ for name, s in servers ~}
%{ if s.role == "aap" ~}
${s.fqdn} ansible_host=${s.public_ip} private_ip=${s.private_ip}
%{ endif ~}
%{ endfor ~}

[quay]
%{ for name, s in servers ~}
%{ if s.role == "quay" ~}
${s.fqdn} ansible_host=${s.public_ip} private_ip=${s.private_ip}
%{ endif ~}
%{ endfor ~}

[image_builder]
%{ for name, s in servers ~}
%{ if s.role == "image-builder" ~}
${s.fqdn} ansible_host=${s.public_ip} private_ip=${s.private_ip}
%{ endif ~}
%{ endfor ~}