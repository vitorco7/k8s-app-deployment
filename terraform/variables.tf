variable "cluster_name" {
  description = "Minikube profile name. Also used as the node name prefix (e.g. 'minikube' → nodes named 'minikube-m02', 'minikube-m03', ...)."
  type        = string
  default     = "minikube"
}

variable "kubernetes_version" {
  description = "Kubernetes version to use for the cluster (e.g. 'v1.32.0')."
  type        = string
  default     = "v1.32.0"
}

variable "availability_zones" {
  description = "List of availability zone labels to assign to worker nodes. One worker node is created per zone. Minimum 3 required to satisfy the Deployment's topologySpreadConstraints."
  type        = list(string)
  default     = ["zone-a", "zone-b", "zone-c"]

  validation {
    condition     = length(var.availability_zones) >= 3
    error_message = "At least 3 availability zones are required. The Deployment's topologySpreadConstraints set minDomains: 3."
  }
}

variable "cpus_per_node" {
  description = "Number of CPUs to allocate to each cluster node."
  type        = number
  default     = 2
}

variable "memory_per_node" {
  description = "Memory in MB to allocate to each cluster node."
  type        = number
  default     = 4096
}
