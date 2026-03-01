# Additional 1password and Synology integration

## What
<!-- Brief description of the idea, request, or change -->
- Add and leverage the 1password Connect ansible collection
- Add the synology provider to terraform

## Why

- Reduce amount manual interventation when managing connections between services and user management
- Automate provisioning of user accounst, NAS drives with NFS permissions
- Automate credential creation and integration with apps
- Will provide greater insight for Claude, Gemini, and Codex when debugging errors and issues

## Notes

- 1password Ansible Collection is an Official 1password project
  - https://developer.1password.com/docs/connect/ansible-collection/
- Terraform Synology Provider is developed and supported by the official Synology Community
  - https://registry.terraform.io/providers/synology-community/synology/latest
  - https://github.com/synology-community/terraform-provider-synology