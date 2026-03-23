terraform {
  required_version = ">= 1.6"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

#  Cluster
resource "null_resource" "minikube_cluster" {
  triggers = {
    cluster_name = var.cluster_name
    nodes        = tostring(1 + length(var.availability_zones))
    cpus         = tostring(var.cpus_per_node)
    memory       = tostring(var.memory_per_node)
    k8s_version  = var.kubernetes_version
  }

  provisioner "local-exec" {
    command = <<-EOT
      minikube delete -p ${var.cluster_name} 2>/dev/null || true
      minikube start \
        -p ${var.cluster_name} \
        --driver=docker \
        --nodes=${1 + length(var.availability_zones)} \
        --cpus=${var.cpus_per_node} \
        --memory=${var.memory_per_node} \
        --kubernetes-version=${var.kubernetes_version} \
        --addons=ingress,metrics-server
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = "minikube delete -p ${self.triggers.cluster_name} || true"
  }
}

# Zone labels 
#   minikube        → control-plane (index 1, skipped)
#   minikube-m02    → first worker  (index 2)
#   minikube-m03    → second worker (index 3)
#   minikube-m04    → third worker  (index 4)
locals {
  worker_nodes = [
    for i, zone in var.availability_zones : {
      name = "${var.cluster_name}-m${format("%02d", i + 2)}"
      zone = zone
    }
  ]
}

resource "null_resource" "zone_labels" {
  for_each = {
    for node in local.worker_nodes : node.name => node.zone
  }

  triggers = {
    node_name = each.key
    zone      = each.value
    cluster   = var.cluster_name
  }

  provisioner "local-exec" {
    command = "kubectl label node ${each.key} topology.kubernetes.io/zone=${each.value} --overwrite --context=${var.cluster_name}"
  }

  depends_on = [null_resource.minikube_cluster]
}
