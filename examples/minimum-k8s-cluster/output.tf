output "security_group_name" {
  description = "The security group used in the cluster"
  value       = module.minimum_k8s_cluster.security_group_name
}

output "worker_info" {
  description = "The worker information in cluster"
  value       = module.minimum_k8s_cluster.worker_info
}

output "control_plane_info" {
  description = "The control plane infomation in cluster"
  value       = module.minimum_k8s_cluster.control_plane_info
}