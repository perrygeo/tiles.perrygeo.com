########################################
# NixOS rebuild
#
# The instance boots the official NixOS AMI and is then configured in place with
# the flake at the repo root. Changing flake.nix / flake.lock /
# nixos/configuration.nix / the martin patch makes Terraform replace this small
# terraform_data resource, which re-runs the provisioner against the same EC2
# instance — the instance itself is NOT replaced.
#
# To force a rebuild without editing files:
#
#   make rebuild
#
########################################

resource "terraform_data" "nixos_rebuild" {
  depends_on = [
    aws_spot_instance_request.tiles,
    aws_eip_association.tiles,
  ]

  triggers_replace = {
    instance_id = aws_spot_instance_request.tiles.spot_instance_id
    flake       = filesha256("${path.module}/../flake.nix")
    lock        = filesha256("${path.module}/../flake.lock")
    config      = filesha256("${path.module}/../nixos/configuration.nix")
    patch       = filesha256("${path.module}/../nixos/libdeflate-gcc16.patch")
  }

  provisioner "local-exec" {
    working_dir = "${path.module}/.."
    command     = <<-EOT
      set -euo pipefail
      # The dev machine may export nix-ld in LD_LIBRARY_PATH (for unpackaged
      # binaries). That path is built against the dev machine's glibc and poisons
      # the flake's own nix binary; clear it so nix resolves libs from its store.
      unset LD_LIBRARY_PATH NIX_LD NIX_LD_LIBRARY_PATH
      key="${pathexpand(var.ssh_private_key_path)}"
      # UserKnownHostsFile=/dev/null: a replaced EC2 instance gets a new host key,
      # which would otherwise collide with the stale known_hosts entry for the EIP.
      ssh_opts="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -i $key"
      for i in $(seq 1 60); do
        if ssh $ssh_opts root@${aws_eip.tiles.public_ip} true 2>/dev/null; then
          NIX_SSHOPTS="$ssh_opts" \
            nixos-rebuild switch \
              --flake .#tiles \
              --target-host root@${aws_eip.tiles.public_ip}
          exit 0
        fi
        echo "waiting for SSH on ${aws_eip.tiles.public_ip} ($i/60)..."
        sleep 5
      done
      echo "instance did not become reachable over SSH" >&2
      exit 1
    EOT
  }
}
