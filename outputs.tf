output "control_plane_ip" {
  value = aws_instance.control_plane.public_ip
}

output "workers_ips" {
  value = aws_instance.workers[*].public_ip
}
