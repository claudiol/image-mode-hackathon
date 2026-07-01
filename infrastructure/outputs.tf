output "public_bastion_ip" {
  value       = aws_instance.bastion.public_ip
  description = "The public facing IPv4 target for structural SSH proxying"
}

output "internal_control_plane_ips" {
  value = {
    satellite = aws_instance.satellite.private_ip
    idm       = aws_instance.idm.private_ip
    quay      = aws_instance.quay.private_ip
    jenkins   = aws_instance.jenkins.private_ip
    ansible   = aws_instance.ansible.private_ip
  }
  description = "VPC Private IP infrastructure routing target list"
}
