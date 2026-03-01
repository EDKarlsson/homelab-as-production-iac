# Remote State Backend — PostgreSQL
#
# IMPORTANT: This backend requires the PostgreSQL VM (10.0.0.44) to be
# deployed and accessible first. See docs/guides/terraform-remote-state.md
# for the full migration procedure.
#
# Connection string is read from the PG_CONN_STR environment variable.
# Format: postgres://terraform:<password>@10.0.0.44:5432/terraform_state
#
# To activate:
#   1. Deploy the k3s module (which creates the PostgreSQL VM)
#   2. Verify connectivity: psql -h 10.0.0.44 -U terraform -d terraform_state
#   3. Uncomment the backend block below
#   4. Run: terraform init -migrate-state
#   5. Confirm: "yes" when prompted to copy state

terraform {
  backend "pg" {}
}
