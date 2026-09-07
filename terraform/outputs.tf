output "vm_ip" {
  description = "Static deployment address of the demo VM."
  value       = var.vm_ip
}

output "ansible_inventory" {
  description = "Generated Ansible inventory path."
  value       = local_file.ansible_inventory.filename
}
