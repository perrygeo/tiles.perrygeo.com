output "instance_id" {
  description = "Spot instance ID."
  value       = aws_spot_instance_request.tiles.spot_instance_id
}

output "elastic_ip" {
  description = "Elastic IP of the tile server — stable across spot stop/start."
  value       = aws_eip.tiles.public_ip
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain. Point tiles.perrygeo.com here."
  value       = aws_cloudfront_distribution.tiles.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (used by `make purge` for invalidations)."
  value       = aws_cloudfront_distribution.tiles.id
}

output "ssh_command" {
  description = "Convenience SSH command (uses ssh_private_key_path)."
  value       = "ssh -i ${var.ssh_private_key_path} root@${aws_eip.tiles.public_ip}"
}
