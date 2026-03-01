# Guide: Terraform Remote State with PostgreSQL

This guide covers migrating Terraform state from the default local backend to the PostgreSQL (`pg`)
backend. The PostgreSQL VM at `10.0.0.45` serves double duty: K3s external datastore **and**
Terraform remote state storage.

**Why this matters:** Local state (`terraform.tfstate` on disk) is fragile — a lost laptop or
accidental deletion means rebuilding state from scratch. The `pg` backend stores state in PostgreSQL
with built-in advisory-lock-based locking, preventing concurrent modifications without any extra
infrastructure (no S3, no DynamoDB, no Consul).

## Key documentation

| Topic | URL |
|---|---|
| Backend Type: pg | https://developer.hashicorp.com/terraform/language/backend/pg |
| Backend Configuration | https://developer.hashicorp.com/terraform/language/backend/configuration |
| State Locking | https://developer.hashicorp.com/terraform/language/state/locking |
| terraform init (migration) | https://developer.hashicorp.com/terraform/cli/commands/init |

---

## Why PostgreSQL over other backends?

| Backend | Pros | Cons | Fit for this homelab |
|---|---|---|---|
| **Local** (default) | Zero setup | No locking, no sharing, fragile | Current — needs replacing |
| **S3 + DynamoDB** | Industry standard, versioning | Requires AWS account or MinIO + DynamoDB-compatible store | Over-engineered for homelab |
| **Consul** | Built-in locking, HA | Another service to manage | Adds complexity |
| **pg** | Reuses existing PostgreSQL VM, built-in locking, simple | Single point of failure | Best fit — already have the VM |

The PostgreSQL VM (`10.0.0.45`) is already planned for K3s's external datastore. Adding a
`terraform_state` database to the same instance costs nothing and avoids new infrastructure.

---

## Prerequisites

Before starting, you need:

1. **PostgreSQL VM deployed** — the k3s module creates this at `10.0.0.45` (see [Guide 3](./cloning-k3s-vms.md))
2. **Network connectivity** — your workstation can reach `10.0.0.45:5432` on VLAN02 (10.0.0.0/24)
3. **Database credentials** — the `terraform` user password (stored in 1Password, same as `postgres_password`)
4. **Existing Terraform state** — you should have a working `terraform plan` with local state before migrating

---

## How the pg backend works

The `pg` backend stores state as a JSON blob in a PostgreSQL table. Key behaviors:

- **Schema:** Creates `terraform_remote_state` schema (configurable via `PG_SCHEMA_NAME`)
- **Table:** Creates a `states` table keyed by workspace name (`default` for single-workspace setups)
- **Locking:** Uses PostgreSQL advisory locks (session-based, auto-release on disconnect)
- **No `force-unlock`:** Advisory locks can't be force-unlocked — they release when the session ends.
  If a lock is stuck, the PostgreSQL connection holding it has already dropped and the lock is gone.
- **Backend block limitations:** Cannot use Terraform variables, data sources, or interpolation.
  Backend configuration is parsed before providers initialize. Use environment variables instead.

**Docs:** [Backend Type: pg](https://developer.hashicorp.com/terraform/language/backend/pg)

---

## Phase 1: Prepare (before PostgreSQL VM exists)

These changes are already committed. Review them to understand what's in place.

### 1.1 — backend.tf (commented out)

The file `infrastructure/backend.tf` contains the backend block, commented out until the database
is available:

```hcl
# terraform {
#   backend "pg" {}
# }
```

The empty block reads **all** configuration from environment variables. This keeps credentials
out of code entirely.

**Docs:** [Partial Configuration](https://developer.hashicorp.com/terraform/language/backend/configuration#partial-configuration)

### 1.2 — Environment variable

The connection string is passed via `PG_CONN_STR`:

```bash
# Format:
PG_CONN_STR="postgres://terraform:<password>@10.0.0.45:5432/terraform_state"
```

This variable is documented in `.env.example` (commented out until migration).

### 1.3 — Database provisioning

The PostgreSQL cloud-config template (`infrastructure/modules/k3s/cloud-configs/postgresql.yml.tpl`)
creates the `terraform_state` database and `terraform` user automatically when the VM boots:

```bash
sudo -u postgres createdb terraform_state
sudo -u postgres psql -c "CREATE USER terraform WITH ENCRYPTED PASSWORD '...';"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE terraform_state TO terraform;"
```

The `pg_hba.conf` allows the `terraform` user to connect from the homelab network (10.0.0.0/24).

---

## Phase 2: Deploy the PostgreSQL VM

Follow these guides in order:

1. **[Guide 2: Creating a VM Template](./creating-vm-template.md)** — if you haven't already
2. **[Guide 3: Cloning K3s VMs](./cloning-k3s-vms.md)** — deploys all k3s module VMs, including PostgreSQL

After deployment, verify the VM is running:

```bash
# SSH into the PostgreSQL VM
ssh <username>@10.0.0.45

# Check PostgreSQL is running
systemctl status postgresql

# Verify the terraform_state database exists
sudo -u postgres psql -l | grep terraform_state
```

---

## Phase 3: Verify database connectivity

From your workstation (where you run Terraform), verify you can connect:

```bash
# Test connection with psql
psql -h 10.0.0.45 -U terraform -d terraform_state -c "SELECT 1;"
# Enter the terraform user password when prompted

# Or test with the full connection string
psql "postgres://terraform:<password>@10.0.0.45:5432/terraform_state" -c "SELECT 1;"
```

If the connection fails, check:

- **Firewall:** Is port 5432 open on the PostgreSQL VM?
- **pg_hba.conf:** Does it allow your workstation's IP? (should allow 10.0.0.0/24)
- **listen_addresses:** Is PostgreSQL listening on all interfaces? (`listen_addresses = '*'`)
- **Routing:** Can your workstation reach the 10.0.0.0/24 network?

---

## Phase 4: Migrate state

### 4.1 — Store credentials in 1Password

Create a 1Password item for the Terraform state database connection string:

```bash
# Create a new item in the Homelab vault
op item create \
  --vault "Homelab" \
  --category "Database" \
  --title "Terraform_State_PostgreSQL" \
  --url "postgres://terraform@10.0.0.45:5432/terraform_state" \
  "credentials.connection_string[password]=postgres://terraform:<password>@10.0.0.45:5432/terraform_state"
```

Or create the item manually in the 1Password app/web interface.

### 4.2 — Add to .env.saved

Add the connection string to your `.env.saved` file (the file you `source` before running Terraform):

```bash
# Terraform Remote State Backend
PG_CONN_STR="postgres://terraform:<password>@10.0.0.45:5432/terraform_state"
```

Or load it from 1Password at runtime:

```bash
# Using op CLI secret reference
export PG_CONN_STR="$(op read 'op://Homelab/Terraform_State_PostgreSQL/credentials/connection_string')"
```

### 4.3 — Uncomment the backend block

Edit `infrastructure/backend.tf` — uncomment the backend block:

```hcl
terraform {
  backend "pg" {}
}
```

### 4.4 — Run the migration

```bash
# Source your environment (loads PG_CONN_STR)
source .env.saved

# Change to the infrastructure directory
cd infrastructure

# Initialize with migration
terraform init -migrate-state
```

Terraform will detect the backend change and prompt:

```
Do you want to copy existing state to the new backend?

  Pre-existing state was found while migrating the previous "local" backend to
  the newly configured "pg" backend. No existing state was found in the newly
  configured "pg" backend. Do you want to copy this state to the new "pg"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value:
```

Type **`yes`** to copy your local state to PostgreSQL.

### 4.5 — Verify the migration

```bash
# Run a plan — should show NO infrastructure changes
terraform plan

# Verify state is in PostgreSQL
psql "$PG_CONN_STR" -c "SELECT workspace FROM terraform_remote_state.states;"
# Should output: default

# Check that local state was backed up
ls -la terraform.tfstate*
# Should see: terraform.tfstate.backup
```

If `terraform plan` shows no changes, the migration was successful. The local
`terraform.tfstate.backup` is a safety copy — keep it until you're confident the
remote state is working.

---

## Rollback: Reverting to local state

If something goes wrong, you can revert to local state:

### Option 1: Migrate back (recommended)

```bash
# Comment out the backend block in backend.tf, then:
terraform init -migrate-state
# Type "yes" when prompted to copy state back to local
```

### Option 2: Restore from backup

```bash
# Comment out the backend block in backend.tf
# Restore the backup file
cp terraform.tfstate.backup terraform.tfstate
terraform init
```

---

## Operational notes

### Backup and restore

The PostgreSQL VM already has automated backups (`/usr/local/bin/backup-k3s-db.sh`), but those
back up the `k3s` database. For the Terraform state database specifically:

```bash
# Manual backup of terraform state database
ssh <username>@10.0.0.45 "sudo -u postgres pg_dump terraform_state" > terraform_state_backup.sql

# Restore
ssh <username>@10.0.0.45 "sudo -u postgres psql terraform_state" < terraform_state_backup.sql
```

Consider adding `terraform_state` to the existing backup cron job on the PostgreSQL VM.

### Advisory lock behavior

- Locks are **session-based** — they release automatically when your Terraform process exits
- No stale locks to clean up (unlike DynamoDB lock records)
- `terraform force-unlock` is **not supported** for the pg backend
- If you see a lock error, it means another `terraform apply` is genuinely running — wait for it
- In the rare case of a stuck session, a DBA can terminate it:
  ```sql
  SELECT pg_terminate_backend(pid)
  FROM pg_stat_activity
  WHERE application_name LIKE '%terraform%';
  ```

**Docs:** [State Locking](https://developer.hashicorp.com/terraform/language/state/locking)

### Connection pooling warning

Do **not** place a connection pooler (PgBouncer, Pgpool-II) between Terraform and PostgreSQL.
Advisory locks are session-based and require a direct, persistent connection. Connection poolers
that multiplex sessions will break locking.

### Multiple workspaces

If you later use Terraform workspaces, each workspace gets its own row in the `states` table.
The default workspace is named `default`. No additional configuration is needed.

---

## Environment variable reference

| Variable | Description | Example |
|---|---|---|
| `PG_CONN_STR` | Full PostgreSQL connection string | `postgres://terraform:pass@10.0.0.45:5432/terraform_state` |
| `PG_SCHEMA_NAME` | Schema name (optional) | `terraform_remote_state` (default) |
| `PG_SKIP_SCHEMA_CREATION` | Skip auto-creating schema | `false` (default) |
| `PG_SKIP_TABLE_CREATION` | Skip auto-creating states table | `false` (default) |
| `PG_SKIP_INDEX_CREATION` | Skip auto-creating index | `false` (default) |

For this homelab, only `PG_CONN_STR` is needed. The defaults are fine for everything else.
