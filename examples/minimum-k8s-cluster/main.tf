locals {
  region            = "jp-west-1"
  availability_zone = "west-11"

  instance_type_cp = "e-medium"
  instance_type_wk = "e-medium"

  instance_count_wk = 2
}

#####
# Provider
#
provider "nifcloud" {
  region = local.region
}

#####
# Module
#
module "minimum_k8s_cluster" {
  source = "../../"

  availability_zone = local.availability_zone
  prefix            = "002"

  instance_key_name = var.instance_key_name

  instance_count_wk = local.instance_count_wk

  instance_type_cp = local.instance_type_cp
  instance_type_wk = local.instance_type_wk
}

#####
# Security Group
#
resource "nifcloud_security_group_rule" "ssh_from_working_server" {
  security_group_names = [
    module.minimum_k8s_cluster.security_group_name.control_plane,
    module.minimum_k8s_cluster.security_group_name.worker,
  ]
  type      = "IN"
  from_port = 22
  to_port   = 22
  protocol  = "TCP"
  cidr_ip   = var.working_server_ip
}