locals {
  instance_name     = "eac-demo-vm"
  repository_root   = abspath("${path.module}/..")
  cloud_init_path   = "${path.module}/cloud-init.generated.yaml"
  inventory_path    = "${local.repository_root}/ansible/inventory/generated.ini"
  deploy_public_key = trimspace(var.deploy_ssh_public_key)
}

resource "local_file" "cloud_init" {
  filename        = local.cloud_init_path
  file_permission = "0600"
  content = templatefile("${path.module}/templates/cloud-init.yaml.tftpl", {
    deploy_ssh_public_key = local.deploy_public_key
    vm_ip                 = var.vm_ip
  })
}

resource "local_file" "ansible_inventory" {
  filename        = local.inventory_path
  file_permission = "0600"
  content         = <<-EOT
    [demo]
    demo_vm ansible_host=${var.vm_ip} ansible_user=deploy

    [demo:vars]
    ansible_python_interpreter=/usr/bin/python3
    EOT
}

resource "terraform_data" "multipass_vm" {
  triggers_replace = [local_file.cloud_init.content_sha256, var.multipass_network]

  input = {
    instance_name    = local.instance_name
    multipass_script = "${local.repository_root}/scripts/multipass.sh"
  }

  provisioner "local-exec" {
    command = "${local.repository_root}/scripts/multipass.sh apply ${local_file.cloud_init.filename}"
    environment = {
      INSTANCE_NAME     = local.instance_name
      MULTIPASS_NETWORK = var.multipass_network
      VM_IP             = var.vm_ip
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "${self.input.multipass_script} destroy"
    environment = {
      INSTANCE_NAME = self.input.instance_name
    }
  }

  depends_on = [local_file.ansible_inventory]
}
