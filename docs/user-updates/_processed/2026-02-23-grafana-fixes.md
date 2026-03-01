# Broken Grafana Dashboards

## What

1. There are grafana dashboards that do not show telemetry:
    - Proxmox VE Cluster
    - CI/CD Pipeline
    - Homelab Applications
    - Kubernetes
        - Compute Resources
            - Namespace (Pods)
            - Namespace (Workloads)
            - Node (Pods)
            - Pod
            - Controller Manager
        - Networking
            - Cluster
            - Namespace (Pods)
            - Namespace (Workloads)
        - Scheduler
2. Want more dashboards for the new applications we've deployed
3. More application log aggregation
4. Alerting seems to be constantly sending messages to slack. Possible solution:
    - Increase severity threshold before sending alert
    - Figure out why the issue is persisting in kubernetes
    - Make some kind of plugin or service that does analysis and triages alerts before sending them out.

## Why
<!-- Optional: motivation, context, or problem being solved -->

## Notes
<!-- Optional: constraints, preferences, links, screenshots -->
