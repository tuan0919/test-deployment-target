# Everything-as-Code demo design

## Purpose

Provide a small, repeatable local demonstration of application code, containerization, infrastructure as code, configuration as code, pipeline as code, deployment, backup/restore, and manual rollback. It is deliberately not a production architecture.

## Decisions

- One Multipass VM, `eac-demo-vm`, with 2 vCPU, 2 GB RAM, 10 GB disk, and bridge address `10.13.31.15` on `localbr`.
- Terraform is the lifecycle entry point. A `terraform_data` resource calls an idempotent Multipass CLI adapter: third-party Multipass Terraform providers are intentionally excluded.
- An Express REST API and PostgreSQL run as two Docker Compose services on the VM.
- PostgreSQL storage is bind-mounted at `/srv/eac-demo/persist/postgres`; `/srv/eac-demo/persist/predeploy` holds a human-inspectable `pg_dump`.
- Ansible configures the VM; Jenkins orchestrates the existing CLI tools without implementing their logic itself.
- Docker images use the immutable commit SHA. Deployment never relies on `latest`.
- Kopia runs on the VM and connects directly to the internal Kopia Server. Jenkins supplies credentials for each operation only.
- A failed deployment stops before rollback. Rollback requires an explicit Jenkins parameter and approval.

## Components and boundaries

### Host

- Jenkins runs the repository `Jenkinsfile`, stores credentials, and archives deployment context.
- Terraform renders bootstrap cloud-init and manages the Multipass instance through `scripts/multipass.sh`.
- Ansible connects using `deploy` over SSH and applies the runtime configuration.
- Docker on the Jenkins agent builds and pushes to `gmo021.cansportsvg.com:9443`.

### Services on the internal network

- The private Docker registry stores images at `gmo021.cansportsvg.com:9443/library/eac-demo:<git-sha>`.
- The Kopia Server stores snapshots. It is reachable directly from the VM.

### Multipass VM

- Docker Compose runs a stateless API and PostgreSQL.
- `/srv/eac-demo/persist` is the sole backup/restore target.
- Kopia client snapshots and restores that directory.
- `deploy` owns the runtime directory and is in the `docker` group.

## Bootstrap and credentials

Terraform launches Ubuntu using custom cloud-init. The cloud-init template creates the non-root `deploy` user, writes an injected SSH public key to its `authorized_keys`, disables password SSH authentication, and configures the bridge NIC address. Terraform receives only `deploy_ssh_public_key`; private material is never in Terraform state or Git.

Jenkins credentials are:

| Credential ID | Kind | Use |
| --- | --- | --- |
| `DEPLOY_SSH_KEY` | SSH Username with private key | Ansible and remote scripts as `deploy` |
| `REGISTRY_CREDENTIALS` | Username/Password | `docker login` on Jenkins and VM |
| `REGISTRY_CA_CERT` | Secret file | Registry CA supplied to Ansible |
| `KOPIA_CREDENTIALS` | Username/Password | Short-lived remote Kopia connection |
| `KOPIA_SERVER` | Secret text | Kopia Server endpoint |

The Docker trust store on Jenkins is installed once by an administrator. Ansible installs the same CA on the VM at `/etc/docker/certs.d/gmo021.cansportsvg.com:9443/ca.crt`. The design does not disable TLS verification or use insecure registries.

## Provisioning and configuration

`terraform apply` renders cloud-init and invokes `scripts/multipass.sh apply`. The adapter verifies the instance if it already exists; otherwise it launches it with the stated resources and `localbr` networking. Terraform outputs the VM address and writes an Ansible inventory. `terraform destroy` invokes `scripts/multipass.sh destroy`, which deletes and purges only `eac-demo-vm`.

The Ansible role installs Docker Engine, Compose plugin, Kopia client, the registry CA, application directories, and the Compose/runtime templates. It also applies Docker registry access using temporary credentials during deployment, not as a plaintext permanent Docker config committed to the VM.

## Application contract

- `GET /health` returns success only when the API can query PostgreSQL.
- `GET /version` returns the immutable image version.
- `GET /notes` lists persisted notes.
- `POST /notes` creates a persisted note.

The demo creates a note before a deliberately defective v1.2 release. The defective version makes health fail, enabling the manual rollback story without special rollback-only code.

## Backup, deploy, and rollback

`backup.sh` runs a PostgreSQL dump into `persist/predeploy`, stops Compose for a filesystem-consistent snapshot, executes `kopia snapshot create /srv/eac-demo/persist`, restarts Compose, and emits the snapshot ID. This short outage is an intentional demo trade-off.

`deploy.sh` receives one immutable image reference, pulls it, updates the Compose environment, starts the stack, and records the deployed image outside the restore target. `health-check.sh` retries `/health`, then verifies `/version` and `/notes`.

On failure, Jenkins preserves the pre-deploy snapshot ID and prior image reference in an archived `rollback-context.json`; it does not restore automatically.

With `RUN_ROLLBACK=true`, an approval gate starts `rollback.sh`:

1. Stop Compose.
2. Create an optional safety snapshot.
3. Restore the selected pre-deploy snapshot to a staging directory.
4. Replace `/srv/eac-demo/persist` while PostgreSQL is stopped.
5. Deploy `ROLLBACK_IMAGE`.
6. Run the normal health/version/notes verification.

## Pipeline

The repository Jenkinsfile orchestrates:

```text
Checkout -> Unit Test -> Build Image -> Push Registry
-> Terraform Apply -> Ansible Configure -> Integration Test
-> Pre-deploy Kopia Snapshot -> Deploy -> Health Check
```

The separate conditional/manual rollback path requires `RUN_ROLLBACK`, `KOPIA_SNAPSHOT_ID`, and `ROLLBACK_IMAGE`. Every secret is injected through Jenkins credential bindings, never interpolated into a committed command, state file, image, or log.

## Explicit exclusions

No Kubernetes, Helm, Terraform Multipass provider, Vault, HA, multi-node database, automatic rollback, monitoring stack, or migration framework. The point is a transparent demonstration, not production completeness.

## Verification and demo acceptance

1. `terraform destroy`, `terraform apply`, and Ansible recreate the environment.
2. A v1.1 pipeline build publishes an immutable image and passes health checks.
3. A note created at runtime survives normal deployment.
4. Before v1.2, Kopia snapshot ID is captured.
5. Deliberately defective v1.2 fails health and does not auto-rollback.
6. Manual rollback restores that snapshot and v1.1 image; health, version, and the pre-v1.2 note all pass.
