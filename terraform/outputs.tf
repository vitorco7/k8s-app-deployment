output "cluster_name" {
  description = "Minikube profile name. Use this as the kubectl context: kubectl config use-context <value>."
  value       = var.cluster_name
}

output "worker_zone_assignments" {
  description = "Map of worker node names to their assigned availability zone labels."
  value = {
    for node in local.worker_nodes : node.name => node.zone
  }
}
