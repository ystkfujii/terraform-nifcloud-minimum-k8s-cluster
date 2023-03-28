output "security_group_name" {
  description = "The security group used in the cluster"
  value = {
    control_plane = nifcloud_security_group.cp.group_name,
    worker        = nifcloud_security_group.wk.group_name,
  }
}

output "private_network_id" {
  description = "The private network used in the cluster"
  value       = nifcloud_private_lan.this.id
}

output "worker_info" {
  description = "The worker information in cluster"
  value = { for v in module.worker : v.instance_id => {
    unique_id  = v.unique_id,
    public_ip  = v.public_ip,
    private_ip = v.private_ip,
  } }
}

output "control_plane_info" {
  description = "The control plane infomation in cluster"
  value = { (module.control_plane.instance_id) : {
    unique_id  = module.control_plane.unique_id,
    public_ip  = module.control_plane.public_ip,
    private_ip = module.control_plane.private_ip,
  } }
}