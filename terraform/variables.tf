variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the instance and subnet."
  type        = string
  default     = "us-east-1a"
}

variable "ami_id" {
  description = "NixOS AMI ID. Leave empty to auto-select the latest nixos/26.05 x86_64 AMI."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type. t3.small (2 GiB) leaves headroom for nixos-rebuild; t3.nano OOMs."
  type        = string
  default     = "t3.small"
}

variable "spot_max_price" {
  description = "Maximum hourly spot price in USD. Bidding at the on-demand price makes interruption essentially impossible."
  type        = string
  default     = "0.0253"
}

variable "key_name" {
  description = "Name of an existing EC2 key pair for SSH access."
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local private key matching key_name, used by nixos-rebuild to SSH into the instance."
  type        = string
  default     = "~/.ssh/id_ed25519"
}

variable "ssh_allowed_cidr" {
  description = "CIDR block allowed to SSH into the instance. Set to <your-ip>/32 in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "root_volume_size_gb" {
  description = "Root EBS volume size in GB."
  type        = number
  default     = 40
}

variable "domain" {
  description = "Domain name CloudFront serves."
  type        = string
  default     = "tiles.perrygeo.com"
}

variable "acm_certificate_arn" {
  description = "ARN of an ACM certificate in us-east-1 for the domain (CloudFront requires us-east-1 certs)."
  type        = string
}
