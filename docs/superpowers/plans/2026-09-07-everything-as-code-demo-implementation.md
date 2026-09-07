# Everything-as-Code Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small API/PostgreSQL demo whose lifecycle, configuration, delivery, backup, restore, and manual rollback are all reproducible as code.

**Architecture:** Terraform invokes an idempotent Multipass CLI adapter and renders cloud-init plus Ansible inventory. Ansible configures Docker, Kopia and registry trust on one VM; Compose runs a stateless Node API and a PostgreSQL container with data bind-mounted below `/srv/eac-demo/persist`. Jenkins only binds credentials and orchestrates the repository scripts.

**Tech Stack:** Node.js 22, Express, PostgreSQL 16, Docker/Compose, Terraform 1.x, Multipass 1.16+, Ansible, Jenkins Declarative Pipeline, Kopia.

**Spec:** `docs/superpowers/specs/2026-09-07-everything-as-code-demo-design.md`

## Global Constraints

- Target VM is `eac-demo-vm`, 2 vCPU, 2 GB RAM, 10 GB disk, address `10.13.31.15` on `localbr`.
- Deploy only `gmo021.cansportsvg.com:9443/library/eac-demo:<git-sha>`; never use `latest` as deployment input.
- No private key, registry password, Kopia password, CA certificate, or real endpoint credential in Git, Terraform state, or durable VM files.
- Terraform owns VM lifecycle; Ansible owns VM configuration; Jenkins only orchestrates CLIs.
- Snapshot `/srv/eac-demo/persist` only when Compose is stopped; data rollback must be explicit and manually approved.
- Do not introduce Kubernetes, Helm, HA, automatic rollback, Vault, or a third-party Multipass provider.

## File structure

- `app/`: Express application, tests, and npm metadata.
- `docker/Dockerfile`, `.dockerignore`, `docker-compose.yml`: image and two-service runtime definition.
- `terraform/`: cloud-init template, Terraform resources, variables and generated inventory contract.
- `ansible/`: inventory template, playbook and a single VM-runtime role.
- `scripts/`: focused, shellcheck-compatible lifecycle, deploy, verification and recovery commands.
- `Jenkinsfile`: declarative orchestration and Jenkins credential bindings.
- `README.md` and `.env.example`: operator setup, credential IDs, demo runbook and non-secret configuration.

---

### Task 1: Implement and test the API contract

**Files:**
- Create: `app/package.json`, `app/src/app.js`, `app/src/server.js`, `app/test/app.test.js`

**Interfaces:**
- Produces `createApp({ pool, version })`, an Express app exposing `GET /health`, `GET /version`, `GET /notes`, and `POST /notes`.
- Consumes `DATABASE_URL` and `APP_VERSION` in `src/server.js`.

- [ ] **Step 1: Write failing route tests with an injected PostgreSQL-pool double.**

```js
const app = createApp({ pool: { query: vi.fn().mockResolvedValue({ rows: [] }) }, version: 'abc123' });
await request(app).get('/version').expect(200, { version: 'abc123' });
await request(app).get('/health').expect(200, { status: 'ok' });
await request(app).post('/notes').send({ text: 'before-v1.2' }).expect(201);
```

- [ ] **Step 2: Run `npm test` in `app/`; verify routes fail because `createApp` does not exist.**

- [ ] **Step 3: Implement `createApp` with parameterized SQL, schema initialization, input validation, and error-to-503 health behavior.**

```js
app.get('/health', async (_req, res) => {
  try { await pool.query('SELECT 1'); res.json({ status: 'ok' }); }
  catch { res.status(503).json({ status: 'error' }); }
});
app.post('/notes', async (req, res) => {
  if (typeof req.body.text !== 'string' || !req.body.text.trim()) return res.status(400).json({ error: 'text is required' });
  const result = await pool.query('INSERT INTO notes(text) VALUES ($1) RETURNING id, text, created_at', [req.body.text.trim()]);
  res.status(201).json(result.rows[0]);
});
```

- [ ] **Step 4: Run `npm test` and `npm run lint`; verify all API tests pass.**
- [ ] **Step 5: Commit application sources and tests with `feat: add persistent notes API`.**

### Task 2: Containerize the API and define its runtime

**Files:**
- Create: `docker/Dockerfile`, `docker-compose.yml`, `.dockerignore`, `.env.example`
- Modify: `app/package.json`

**Interfaces:**
- Consumes `IMAGE_REF`, `APP_VERSION`, `POSTGRES_PASSWORD`, and `POSTGRES_DATA_DIR` from the VM runtime environment.
- Produces services `api` on port 8080 and `postgres`, with API healthcheck at `/health`.

- [ ] **Step 1: Add a failing container smoke command that expects `/health` to return JSON after Compose starts.**

```sh
IMAGE_REF=eac-demo:test APP_VERSION=test POSTGRES_PASSWORD=test POSTGRES_DATA_DIR="$(mktemp -d)" \
  docker compose -f docker-compose.yml up -d --wait
curl --fail --retry 10 http://127.0.0.1:8080/health
```

- [ ] **Step 2: Verify it fails before the Dockerfile and Compose services exist.**
- [ ] **Step 3: Add a non-root Node production image and Compose definition with `postgres:16-alpine`, `depends_on: condition: service_healthy`, and `${POSTGRES_DATA_DIR}:/var/lib/postgresql/data`.**

```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY app/package*.json ./
RUN npm ci --omit=dev
COPY app/src ./src
USER node
CMD ["node", "src/server.js"]
```

- [ ] **Step 4: Build the image and run the smoke command; verify `/health`, `/version`, and a POST/GET notes round trip.**
- [ ] **Step 5: Commit container artifacts with `feat: containerize notes API`.**

### Task 3: Add Terraform Multipass lifecycle and bootstrap contract

**Files:**
- Create: `terraform/main.tf`, `terraform/variables.tf`, `terraform/outputs.tf`, `terraform/templates/cloud-init.yaml.tftpl`, `scripts/multipass.sh`

**Interfaces:**
- Consumes `deploy_ssh_public_key`, `multipass_network=localbr`, `vm_ip=10.13.31.15`.
- Produces `terraform output -raw vm_ip` and `ansible/inventory/generated.ini` with host alias `demo_vm`.

- [ ] **Step 1: Add shell tests using a fake `multipass` executable that assert apply launches once and destroy calls `delete --purge eac-demo-vm`.**

```sh
PATH="$PWD/test/fake-bin:$PATH" scripts/multipass.sh apply test-cloud-init.yaml
test "$(cat test/calls)" = "launch --name eac-demo-vm"
```

- [ ] **Step 2: Run the shell test and verify it fails because the adapter is absent.**
- [ ] **Step 3: Implement the adapter with `set -euo pipefail`, exact instance-name validation, idempotent `multipass info`, explicit CPU/memory/disk/network/cloud-init launch arguments, and a destroy-only exact name.**

```sh
case "${1:-}" in
  apply) multipass info "$INSTANCE" >/dev/null 2>&1 || multipass launch 24.04 --name "$INSTANCE" --cpus 2 --memory 2G --disk 10G --network "$NETWORK" --cloud-init "$2" ;;
  destroy) multipass delete --purge "$INSTANCE" ;;
  *) exit 64 ;;
esac
```

- [ ] **Step 4: Add Terraform `terraform_data` provisioners and a cloud-init template that creates `deploy`, injects only the public key, disables password SSH authentication, and configures the bridge address. Run `terraform fmt -check` and `terraform validate`.**
- [ ] **Step 5: Commit Terraform lifecycle code with `feat: manage demo VM through Terraform`.**

### Task 4: Configure the VM with Ansible

**Files:**
- Create: `ansible/ansible.cfg`, `ansible/inventory/hosts.ini.example`, `ansible/playbooks/configure.yml`, `ansible/roles/demo_runtime/{defaults/main.yml,tasks/main.yml,handlers/main.yml,templates/runtime.env.j2,templates/docker-compose.yml.j2}`

**Interfaces:**
- Consumes `registry_ca_cert_path` (controller-local credential file), `registry_host`, `registry_username`, `registry_password`, and generated inventory host `demo_vm`.
- Produces Docker/Compose/Kopia, `/srv/eac-demo/{app,persist,state}`, runtime environment, registry CA trust, and `deploy` Docker-group access.

- [ ] **Step 1: Add an Ansible Molecule-like syntax/lint fixture and assert the role declares no plaintext credential default.**
- [ ] **Step 2: Run `ansible-playbook --syntax-check playbooks/configure.yml`; verify it fails until the playbook exists.**
- [ ] **Step 3: Implement package installation, directory ownership, Docker group membership, CA copy mode `0644`, runtime template mode `0600`, Compose template deployment, and `no_log: true` around registry login.**

```yaml
- name: Install registry CA
  ansible.builtin.copy:
    src: "{{ registry_ca_cert_path }}"
    dest: "/etc/docker/certs.d/{{ registry_host }}/ca.crt"
    owner: root
    group: root
    mode: '0644'
```

- [ ] **Step 4: Run syntax check and `ansible-lint` if installed; execute the playbook twice against the VM and verify the second recap changes nothing.**
- [ ] **Step 5: Commit Ansible runtime role with `feat: configure demo VM with Ansible`.**

### Task 5: Implement deployment, verification, backup, restore, and rollback scripts

**Files:**
- Create: `scripts/deploy.sh`, `scripts/health-check.sh`, `scripts/backup.sh`, `scripts/restore.sh`, `scripts/rollback.sh`, `scripts/test-scripts.sh`

**Interfaces:**
- `deploy.sh IMAGE_REF` writes `/srv/eac-demo/state/current-image` and starts Compose.
- `backup.sh` prints one Kopia snapshot ID after a `pg_dump` and stopped-Compose snapshot.
- `restore.sh SNAPSHOT_ID` restores to a staging directory then replaces only `/srv/eac-demo/persist` while Compose is stopped.
- `rollback.sh SNAPSHOT_ID IMAGE_REF` performs safety snapshot, restore, deploy, and `health-check.sh`.

- [ ] **Step 1: Write fake Docker/Compose/Kopia tests that assert `backup.sh` orders dump, stop, snapshot, start and that `rollback.sh` does not deploy before restore.**

```sh
scripts/backup.sh | tee output
grep -qx 'snapshot-id: snap-123' output
test "$(paste -sd, test/calls)" = 'pg_dump,compose-down,kopia-snapshot,compose-up'
```

- [ ] **Step 2: Run the test harness; verify it fails while scripts are absent.**
- [ ] **Step 3: Implement scripts using `set -euo pipefail`, argument validation, `trap` to restart Compose after backup errors, staging-only Kopia restore, and `curl --fail --retry-all-errors` verification. Never echo secret values.**

```sh
SNAPSHOT_ID="$1"
STAGING="$(mktemp -d /srv/eac-demo/restore.XXXXXX)"
docker compose --env-file "$RUNTIME_ENV" -f "$COMPOSE_FILE" down
kopia snapshot restore "$SNAPSHOT_ID" --target-path "$STAGING"
mv "$PERSIST_DIR" "${PERSIST_DIR}.pre-restore"
mv "$STAGING/persist" "$PERSIST_DIR"
```

- [ ] **Step 4: Run shell tests and `shellcheck scripts/*.sh`; then do a live v1.1 → snapshot → intentionally failing image → explicit rollback rehearsal.**
- [ ] **Step 5: Commit recovery scripts with `feat: add explicit data backup and rollback`.**

### Task 6: Add Jenkins orchestration and operator documentation

**Files:**
- Create: `Jenkinsfile`
- Modify: `README.md`, `.env.example`

**Interfaces:**
- Jenkins parameters: `RUN_ROLLBACK` (boolean), `KOPIA_SNAPSHOT_ID` (string), `ROLLBACK_IMAGE` (string).
- Jenkins bindings: `DEPLOY_SSH_KEY`, `REGISTRY_CREDENTIALS`, `REGISTRY_CA_CERT`, `KOPIA_CREDENTIALS`, `KOPIA_SERVER`.
- Produces archived `rollback-context.json` holding no secrets, only snapshot ID and prior image reference.

- [ ] **Step 1: Write a Jenkinsfile static test that asserts required stages, `withCredentials`, immutable `${GIT_COMMIT}` tag, and the manual `input` gate exist.**

```sh
rg "stage\('Pre-deploy Kopia Snapshot'\)" Jenkinsfile
rg "credentialsId: 'DEPLOY_SSH_KEY'" Jenkinsfile
rg "input message: 'Approve explicit rollback" Jenkinsfile
```

- [ ] **Step 2: Run the static test and verify it fails with the empty Jenkinsfile.**
- [ ] **Step 3: Implement declarative stages: Checkout, Unit Test, Build Image, Push Registry, Terraform Apply, Ansible Configure, Integration Test, Snapshot, Deploy, Health Check, and conditional Rollback. Bind all credentials only to their required scope, quote shell variables, mask secrets, and archive rollback context.**

```groovy
when { expression { return params.RUN_ROLLBACK } }
steps {
  input message: 'Approve explicit rollback of image and persistent data', ok: 'Rollback'
  sh './scripts/rollback.sh "$KOPIA_SNAPSHOT_ID" "$ROLLBACK_IMAGE"'
}
```

- [ ] **Step 4: Run the Jenkinsfile static test, `git diff --check`, Terraform validation, Ansible syntax check, app tests, and shell tests.**
- [ ] **Step 5: Document exact Jenkins credential setup, CA installation, local recreate commands, deliberate bad v1.2 workflow, snapshot ID selection, rollback procedure, destroy command, and all exclusions. Commit with `feat: orchestrate everything-as-code demo`.**

## Final verification

- [ ] Run `terraform destroy` and `terraform apply` with a public key supplied only through `TF_VAR_deploy_ssh_public_key`.
- [ ] Run the Ansible playbook twice and confirm the second run is idempotent.
- [ ] Build/push v1.1, deploy it, add `before-v1.2` note, and record the pre-deploy snapshot ID.
- [ ] Deploy intentionally unhealthy v1.2 and confirm the pipeline fails without automatic restore.
- [ ] Run explicit rollback with that snapshot and v1.1 image; confirm health succeeds, version is v1.1, and the note content matches the pre-v1.2 state.
