# Everything-as-Code demo

Small interactive Notes CRUD application backed by Node/Express + PostgreSQL, used to demonstrate Terraform, Multipass, Ansible, Docker Registry, Jenkins and Kopia.

The same application serves both the browser UI at `/` and its JSON API. The UI deliberately makes the persistent-data scenario visible: add a note before a release, take a Kopia snapshot, then restore that note during the rollback demo.

## Jenkins credentials

Create these credentials (no secret belongs in Git):

- `DEPLOY_SSH_KEY` — **SSH Username with private key**, username `deploy`.
- `REGISTRY_CREDENTIALS` — registry username/password.
- `REGISTRY_CA_CERT` — registry CA as **Secret file**.
- `POSTGRES_PASSWORD` — database password as **Secret text**.
- `CLOUDFLARE_TUNNEL_TOKEN` — rotated Cloudflare Tunnel token as **Secret text**.
- `KOPIA_CREDENTIALS` — Kopia Server username/password.
- `KOPIA_SERVER` — Kopia Server endpoint as **Secret text**.

Install the registry CA once in the Docker trust store of the Jenkins agent at `/etc/docker/certs.d/gmo021.cansportsvg.com:9443/ca.crt`. Ansible performs the equivalent installation on the VM.

Normal builds also require the `PRODUCTION_URL` parameter. Set it to the bare
Cloudflare HTTPS origin, for example `https://app.example.com`. The pipeline
rejects an empty or non-HTTPS value and verifies this public route after deploy.

## Recreate infrastructure

```sh
export TF_VAR_deploy_ssh_public_key="$(ssh-keygen -y -f /path/to/jenkins-deploy-key)"
terraform -chdir=terraform init
terraform -chdir=terraform apply
ansible-playbook -i ansible/inventory/generated.ini ansible/playbooks/configure.yml \
  -e registry_ca_cert_path=/path/to/registry-ca.crt \
  -e cloudflare_tunnel_token_file=/path/to/cloudflare-tunnel-token \
  -e postgres_password='supply-from-a-secret-store'
```

## Publish the production application

Create a remotely managed tunnel in Cloudflare, rotate its token, and store the
new value in the Jenkins credential `CLOUDFLARE_TUNNEL_TOKEN`. Add a Published
Application route for the production hostname with this origin service:

```text
http://localhost:8080
```

Ansible installs `cloudflared` from Cloudflare's APT repository and manages it
as a systemd service inside the Multipass VM. The application port binds only
to `127.0.0.1`, so Internet traffic reaches it through the outbound tunnel and
not through an inbound VM or host port.

Destroy only the demo VM:

```sh
terraform -chdir=terraform destroy
```

## Demo flow

Run a normal Jenkins build for v1.1. Open the Cloudflare Published Application
hostname and add a note such as `state before v1.2`; the page supports create,
edit, delete and refresh. Record the Kopia output from **Pre-deploy Kopia
Snapshot**. Deploy a deliberately unhealthy v1.2 to make health verification
fail. Start a new build with `RUN_ROLLBACK=true`, set `KOPIA_SNAPSHOT_ID` and
the v1.1 immutable `ROLLBACK_IMAGE`, then approve the input gate. Verify the
restored note in the UI, along with `/health` and `/version`.

## Application tests

`npm test` covers API behavior and an in-memory browser DOM interaction: it loads the UI, submits a note and verifies that the returned persistent note and immutable deployment version are rendered. Jenkins runs this before image construction.

The pipeline runs unit tests and a Gitleaks credential scan in parallel before
building. After deployment, integration and lightweight performance tests run
in parallel through the public Cloudflare hostname. The rollback context artifact contains
the previous image and snapshot command output. Data restore is always explicit;
failed deployment does not trigger automatic rollback.
