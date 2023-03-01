
locals {
  # e.g. east-11 is 11
  az_num = reverse(split("-", var.availability_zone))[0]
  # e.g. east-11 is e11
  az_short_name = "${substr(reverse(split("-", var.availability_zone))[1], 0, 1)}${local.az_num}"

  role_control_plane = "cp"
  role_worker        = "wk"

  private_network_prefix = 24
  private_network_cidr   = "${var.private_network_subnet}/${local.private_network_prefix}"

  # Nubmer of 4th octet begins
  ip_start_cp = 64
  ip_start_wk = 32

  # Port used by the protocol
  port_ssh     = 22
  port_kubectl = 6443
  port_kubelet = 10250

  pod_cidr = "10.244.0.0/16"

  # Version
  v_k8s         = "1.26.1-00"
  v_containerd  = "1.6.18"
  v_runc        = "v1.1.4"
  v_cni_plugins = "v1.2.0"
  v_cri_tools   = "v1.26.0"
  v_flannel     = "v0.21.2"

  # Templatefile
  prepare_kubeadm = templatefile("${path.module}/templates/prepare_kubeadm.tftpl", {
    v_k8s         = local.v_k8s
    v_containerd  = local.v_containerd
    v_runc        = local.v_runc
    v_cni_plugins = local.v_cni_plugins
    v_cri_tools   = local.v_cri_tools
  })
  kubeadm_init = templatefile("${path.module}/templates/kubeadm_init.tftpl", {
    token     = module.kubeadm_token.token
    pod_cidr  = local.pod_cidr
    v_flannel = local.v_flannel
  })
  kubeadm_join = templatefile("${path.module}/templates/kubeadm_join.tftpl", {
    token             = module.kubeadm_token.token
    control_plane_url = "${module.control_plane.private_ip}:6443"
    pod_cidr          = local.pod_cidr
  })
  extra_userdata_cp = templatefile("${path.module}/templates/extra_userdata.tftpl", {
    prepare_kubeadm = local.prepare_kubeadm
    kubeadm_action  = local.kubeadm_init
  })
  extra_userdata_wk = templatefile("${path.module}/templates/extra_userdata.tftpl", {
    prepare_kubeadm = local.prepare_kubeadm
    kubeadm_action  = local.kubeadm_join
  })
}

module "kubeadm_token" {
  source  = "scholzj/kubeadm-token/random"
  version = "1.2.0"
}

#####
# Security Group
#
resource "nifcloud_security_group" "cp" {
  group_name        = "${local.az_short_name}${var.prefix}${local.role_control_plane}"
  description       = "${local.az_short_name} ${var.prefix} ${local.role_control_plane}"
  availability_zone = var.availability_zone
}

resource "nifcloud_security_group" "wk" {
  group_name        = "${local.az_short_name}${var.prefix}${local.role_worker}"
  description       = "${local.az_short_name} ${var.prefix} ${local.role_worker}"
  availability_zone = var.availability_zone
}

#####
# Private LAN
#
resource "nifcloud_private_lan" "this" {
  private_lan_name  = "${var.prefix}lan"
  availability_zone = var.availability_zone
  cidr_block        = local.private_network_cidr
  accounting_type   = var.accounting_type
}

#####
# Module
#
module "control_plane" {
  source  = "ystkfujii/instance/nifcloud"
  version = "0.0.4"

  availability_zone   = var.availability_zone
  instance_name       = "${local.az_short_name}${var.prefix}${local.role_control_plane}${format("%02d", 1)}"
  security_group_name = nifcloud_security_group.cp.group_name
  key_name            = var.instance_key_name
  instance_type       = var.instance_type_cp
  accounting_type     = var.accounting_type

  extra_userdata = local.extra_userdata_cp

  interface_private = {
    ip_address = "${cidrhost(local.private_network_cidr, (local.ip_start_cp + 1))}/${local.private_network_prefix}"
    network_id = nifcloud_private_lan.this.network_id
  }

  depends_on = [
    nifcloud_security_group.cp,
    nifcloud_private_lan.this,
  ]
}

module "worker" {
  source  = "ystkfujii/instance/nifcloud"
  version = "0.0.4"

  count = var.instance_count_wk

  availability_zone   = var.availability_zone
  instance_name       = "${local.az_short_name}${var.prefix}${local.role_worker}${format("%02d", count.index + 1)}"
  security_group_name = nifcloud_security_group.wk.group_name
  key_name            = var.instance_key_name
  instance_type       = var.instance_type_wk
  accounting_type     = var.accounting_type

  extra_userdata = local.extra_userdata_wk

  interface_private = {
    ip_address = "${cidrhost(local.private_network_cidr, (local.ip_start_wk + count.index + 1))}/${local.private_network_prefix}"
    network_id = nifcloud_private_lan.this.network_id
  }

  depends_on = [
    nifcloud_security_group.wk,
    nifcloud_private_lan.this,
    # Wait for kubectl init
    module.control_plane,
  ]
}

#####
# Security Group Rule
#

# ssh
resource "nifcloud_security_group_rule" "ssh_from_cp" {
  security_group_names = [
    nifcloud_security_group.wk.group_name,
  ]
  type                       = "IN"
  from_port                  = local.port_ssh
  to_port                    = local.port_ssh
  protocol                   = "TCP"
  source_security_group_name = nifcloud_security_group.cp.group_name
}

# kubectl
resource "nifcloud_security_group_rule" "kubectl_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name,
  ]
  type                       = "IN"
  from_port                  = local.port_kubectl
  to_port                    = local.port_kubectl
  protocol                   = "TCP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

# kubelet
resource "nifcloud_security_group_rule" "kubelet_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name
  ]
  type                       = "IN"
  from_port                  = local.port_kubelet
  to_port                    = local.port_kubelet
  protocol                   = "TCP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

resource "nifcloud_security_group_rule" "kubelet_from_control_plane" {
  security_group_names = [
    nifcloud_security_group.wk.group_name,
  ]
  type                       = "IN"
  from_port                  = local.port_kubelet
  to_port                    = local.port_kubelet
  protocol                   = "TCP"
  source_security_group_name = nifcloud_security_group.cp.group_name
}
