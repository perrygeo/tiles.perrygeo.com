# Latest NixOS 26.05 x86_64 AMI. 427812963091 is the NixOS AMI publisher
# (see https://nixos.org/download/#nixos-amazon).
data "aws_ami" "nixos" {
  most_recent = true
  owners      = ["427812963091"]

  filter {
    name   = "name"
    values = ["nixos/26.05*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# AWS-managed prefix list for CloudFront edge nodes.
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "tiles" {
  name        = "tiles"
  description = "tiles.perrygeo.com: SSH + HTTP from CloudFront"
  vpc_id      = aws_vpc.tiles.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_allowed_cidr]
  }

  ingress {
    description     = "HTTP from CloudFront"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "tiles" }
}

# ── Spot instance ────────────────────────────────────────────────────────────
#
# aws_spot_instance_request (persistent) is kept, rather than aws_instance +
# instance_market_options, so this repo can adopt the pre-existing spot request
# 1:1 via `terraform import`. If the spot is interrupted and AWS stops it, re-run
# `make apply` to get a new instance; the Elastic IP and CloudFront origin stay
# put.
#
resource "aws_spot_instance_request" "tiles" {
  ami                            = var.ami_id == "" ? data.aws_ami.nixos.id : var.ami_id
  instance_type                  = var.instance_type
  spot_price                     = var.spot_max_price
  spot_type                      = "persistent"
  wait_for_fulfillment           = true
  instance_interruption_behavior = "stop"

  key_name               = var.key_name
  subnet_id              = aws_subnet.tiles.id
  vpc_security_group_ids = [aws_security_group.tiles.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
  }

  tags = { Name = "tiles-spot-request" }

  # Spot requests don't propagate tags to the underlying instance; tag it here.
  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 create-tags \
        --region ${var.region} \
        --resources ${self.spot_instance_id} \
        --tags Key=Name,Value=tiles
    EOT
  }
}

# ── Elastic IP ──────────────────────────────────────────────────────────────
#
# Stable public IP that survives spot stop/start. CloudFront's origin points at
# the EIP's public DNS name, so it never needs updating.
resource "aws_eip" "tiles" {
  domain = "vpc"

  tags = { Name = "tiles" }
}

resource "aws_eip_association" "tiles" {
  allocation_id = aws_eip.tiles.id
  instance_id   = aws_spot_instance_request.tiles.spot_instance_id
}
