ssh_public_key = "" # empty string reads ~/.ssh/id_rsa.pub
dcos_version = "2.0.1"
cluster_name = "private-poc"
num_masters = "3"
num_private_agents = "5"
num_public_agents = "0"
dcos_type = "ee"
# dcos_license_key_contents = "<put your license key here>"
aws_associate_public_ip_address = "false"
admin_ips = ["192.168.0.0/16"]
tags = {
  "environment" = "nonprod"
}
