output "public_ip" {
  value = aws_eip.this.public_ip
}

output "ssh_command" {
  value = "ssh -i ${local_sensitive_file.pem.filename} ubuntu@${aws_eip.this.public_ip}"
}

output "app_url" {
  value = "http://${aws_eip.this.public_ip}"
}

output "jenkins_url" {
  value = "http://${aws_eip.this.public_ip}:8080"
}

output "grafana_url" {
  value = "http://${aws_eip.this.public_ip}:30300"
}

output "prometheus_url" {
  value = "http://${aws_eip.this.public_ip}:30090"
}
