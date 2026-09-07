# Everything-as-Code demo

Small Node/Express + PostgreSQL demo for Terraform, Multipass, Ansible, Docker Registry, Jenkins and Kopia.

## Jenkins credentials

Create these credentials (no secret belongs in Git):

- `DEPLOY_SSH_KEY` — **SSH Username with private key**, username `deploy`.
- `REGISTRY_CREDENTIALS` — registry username/password.
- `REGISTRY_CA_CERT` — registry CA as **Secret file**.
- `POSTGRES_PASSWORD` — database password as **Secret text**.
- `KOPIA_CREDENTIALS` — Kopia Server username/password.
- `KOPIA_SERVER` — Kopia Server endpoint as **Secret text**.

Install the registry CA once in the Docker trust store of the Jenkins agent at `/etc/docker/certs.d/gmo021.cansportsvg.com:9443/ca.crt`. Ansible performs the equivalent installation on the VM.

## Recreate infrastructure

```sh
export TF_VAR_deploy_ssh_public_key="$(ssh-keygen -y -f /path/to/jenkins-deploy-key)"
terraform -chdir=terraform init
terraform -chdir=terraform apply
ansible-playbook -i ansible/inventory/generated.ini ansible/playbooks/configure.yml \
  -e registry_ca_cert_path=/path/to/registry-ca.crt \
  -e postgres_password='supply-from-a-secret-store'
```

Destroy only the demo VM:

```sh
terraform -chdir=terraform destroy
```

## Demo flow

Run a normal Jenkins build for v1.1. Add a note with `POST /notes`, then record the Kopia output from **Pre-deploy Kopia Snapshot**. Deploy a deliberately unhealthy v1.2 to make health verification fail. Start a new build with `RUN_ROLLBACK=true`, set `KOPIA_SNAPSHOT_ID` and the v1.1 immutable `ROLLBACK_IMAGE`, then approve the input gate. Verify `/health`, `/version`, and `/notes`.

The rollback context artifact contains the previous image and snapshot command output. Data restore is always explicit; failed deployment does not trigger automatic rollback.
