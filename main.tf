
locals {
  # e.g. east-11 is 11
  az_num = reverse(split("-", var.availability_zone))[0]
  # e.g. east-11 is e11
  az_short_name = "${substr(reverse(split("-", var.availability_zone))[1], 0, 1)}${local.az_num}"

  role_control_plane = "cp"
  role_worker        = "wk"

  # Private Netrwork
  private_network_prefix = 24
  private_network_cidr   = "${var.private_network_subnet}/${local.private_network_prefix}"

  # Nubmer of 4th octet begins
  ip_start_cp = 64
  ip_start_wk = 32

  private_ip_cp = cidrhost(local.private_network_cidr, (local.ip_start_cp + 1))

  # Port used by the protocol
  port_ssh     = 22
  port_kubectl = 6443
  port_kubelet = 10250
  port_flannel = 8472

  # Port used by cilium
  #  see: https://docs.cilium.io/en/stable/operations/system_requirements/#firewall-rules
  from_port_etcd = 2379
  to_port_etcd   = 2380
  port_vxlan     = 8472
  port_hc        = 4240

  pod_cidr = "10.244.0.0/16"

  # version
  v_k8s       = "1.26.1-00"
  v_flannel   = "v0.21.2"
  v_cri_tools = "v1.26.0"

  v_cilium_cli = "v0.15.7"
  v_cilium     = "1.14.1"

  # containerd
  v_containerd  = "1.6.18"
  v_runc        = "v1.1.4"
  v_cni_plugins = "v1.2.0"

  # cri-o
  v_crio   = "1.26"
  os_image = "xUbuntu_22.04"

  # Templatefile
  prepare_kubeadm = templatefile("${path.module}/templates/prepare_kubeadm.tftpl", {
    v_k8s = local.v_k8s
  })

  # cri
  install_containerd = templatefile("${path.module}/templates/install_containerd.tftpl", {
    v_containerd  = local.v_containerd
    v_runc        = local.v_runc
    v_cni_plugins = local.v_cni_plugins
    v_cri_tools   = local.v_cri_tools
  })
  install_crio = templatefile("${path.module}/templates/install_crio.tftpl", {
    v_crio      = local.v_crio
    v_cri_tools = local.v_cri_tools
    os_image    = local.os_image
  })
  install_cri = var.cri == "containerd" ? local.install_containerd : local.install_crio

  # cni
  install_flannel = templatefile("${path.module}/templates/install_flannel.tftpl", {
    v_flannel = local.v_flannel
  })
  install_cilium = templatefile("${path.module}/templates/install_cilium.tftpl", {
    cli_arch     = "amd64"
    v_cilium     = local.v_cilium
    v_cilium_cli = local.v_cilium_cli
  })
  install_cni = var.cni == "flannel" ? local.install_flannel : local.install_cilium

  kubeadm_init = templatefile("${path.module}/templates/kubeadm_init.tftpl", {
    token    = module.kubeadm_token.token
    pod_cidr = local.pod_cidr
  })
  kubeadm_join = templatefile("${path.module}/templates/kubeadm_join.tftpl", {
    token             = module.kubeadm_token.token
    control_plane_url = "${local.private_ip_cp}:6443"
    pod_cidr          = local.pod_cidr
  })
  extra_userdata_cp = templatefile("${path.module}/templates/extra_userdata.tftpl", {
    prepare_kubeadm = local.prepare_kubeadm
    install_cri     = local.install_cri
    kubeadm_action  = local.kubeadm_init
    install_cni     = local.install_cni
  })
  extra_userdata_wk = templatefile("${path.module}/templates/extra_userdata.tftpl", {
    prepare_kubeadm = local.prepare_kubeadm
    install_cri     = local.install_cri
    kubeadm_action  = local.kubeadm_join
    install_cni     = local.install_cni
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
  version = "0.0.6"

  availability_zone   = var.availability_zone
  instance_name       = "${local.az_short_name}${var.prefix}${local.role_control_plane}${format("%02d", 1)}"
  security_group_name = nifcloud_security_group.cp.group_name
  key_name            = var.instance_key_name
  instance_type       = var.instance_type_cp
  accounting_type     = var.accounting_type

  extra_userdata = local.extra_userdata_cp

  interface_private = {
    ip_address = "${local.private_ip_cp}/${local.private_network_prefix}"
    network_id = nifcloud_private_lan.this.network_id
  }

  depends_on = [
    nifcloud_security_group.cp,
    nifcloud_private_lan.this,
  ]
}

module "worker" {
  source  = "ystkfujii/instance/nifcloud"
  version = "0.0.6"

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

#
# flannel
#

resource "nifcloud_security_group_rule" "flannel_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name
  ]
  type                       = "IN"
  from_port                  = local.port_flannel
  to_port                    = local.port_flannel
  protocol                   = "UDP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

resource "nifcloud_security_group_rule" "flannel_from_control_plane" {
  security_group_names = [
    nifcloud_security_group.wk.group_name,
  ]
  type                       = "IN"
  from_port                  = local.port_flannel
  to_port                    = local.port_flannel
  protocol                   = "UDP"
  source_security_group_name = nifcloud_security_group.cp.group_name
}

#
# cilium
#

resource "nifcloud_security_group_rule" "etcd_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name
  ]
  type                       = "IN"
  from_port                  = local.from_port_etcd
  to_port                    = local.to_port_etcd
  protocol                   = "TCP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

resource "nifcloud_security_group_rule" "vxlan_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name
  ]
  type                       = "IN"
  from_port                  = local.port_vxlan
  to_port                    = local.port_vxlan
  protocol                   = "UDP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

resource "nifcloud_security_group_rule" "health_checks_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name
  ]
  type                       = "IN"
  from_port                  = local.port_hc
  to_port                    = local.port_hc
  protocol                   = "TCP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

resource "nifcloud_security_group_rule" "icmp_from_worker" {
  security_group_names = [
    nifcloud_security_group.cp.group_name
  ]
  type                       = "IN"
  protocol                   = "ICMP"
  source_security_group_name = nifcloud_security_group.wk.group_name
}

resource "nifcloud_security_group_rule" "vxlan_from_control_plane" {
  security_group_names = [
    nifcloud_security_group.wk.group_name
  ]
  type                       = "IN"
  from_port                  = local.port_vxlan
  to_port                    = local.port_vxlan
  protocol                   = "UDP"
  source_security_group_name = nifcloud_security_group.cp.group_name
}

resource "nifcloud_security_group_rule" "health_checks_from_control_plane" {
  security_group_names = [
    nifcloud_security_group.wk.group_name
  ]
  type                       = "IN"
  from_port                  = local.port_hc
  to_port                    = local.port_hc
  protocol                   = "UDP"
  source_security_group_name = nifcloud_security_group.cp.group_name
}

resource "nifcloud_security_group_rule" "icmp_from_control_plane" {
  security_group_names = [
    nifcloud_security_group.wk.group_name
  ]
  type                       = "IN"
  protocol                   = "ICMP"
  source_security_group_name = nifcloud_security_group.cp.group_name
}


