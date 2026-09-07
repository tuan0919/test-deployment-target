variable "deploy_ssh_public_key" {
  description = "Public key for the Jenkins deploy SSH credential."
  type        = string
  sensitive   = true
}

variable "vm_ip" {
  description = "Static address assigned to the Multipass bridge NIC."
  type        = string
  default     = "10.13.31.15"
}

variable "multipass_network" {
  description = "Host bridge passed to multipass launch."
  type        = string
  default     = "localbr"
}
