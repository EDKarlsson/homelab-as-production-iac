# Proxmox Node Hardware Config

## VM Distribution Across Nodes

```mermaid
graph LR
    subgraph UM560["node-02 · 12c / 31 GB"]
        S1VM["k3s-server-1\n4c · 4 GB"]
        A1VM["k3s-agent-1\n6c · 26 GB"]
        T9000["VM 9000\n(Ubuntu template)\n2c · 2 GB"]
    end
    subgraph UM773A["node-03 · 16c / 31 GB"]
        S2VM["k3s-server-2\n4c · 4 GB"]
        A2VM["k3s-agent-2\n10c · 24 GB"]
    end
    subgraph UM773B["node-04 · 16c / 31 GB"]
        S3VM["k3s-server-3\n4c · 4 GB"]
        A3VM["k3s-agent-3\n8c · 24 GB"]
    end
    subgraph HX77G["node-01 · 16c / 32 GB"]
        A4VM["k3s-agent-4\n12c · 24 GB"]
        PGPRIM["pg-primary (VM 520)\n2c · 4 GB"]
        OP1["1password-connect (CT 200)\n2c · 2 GB"]
    end
    subgraph ORIGIN["node-05 · 12c / 67 GB"]
        A5VM["k3s-agent-5\n10c · 60 GB"]
        PGSTBY["pg-standby (VM 521)\n2c · 4 GB"]
        OP2["1password-connect (CT 201)\n2c · 2 GB"]
    end

    style UM560 fill:#eff6ff,stroke:#93c5fd
    style UM773A fill:#eff6ff,stroke:#93c5fd
    style UM773B fill:#eff6ff,stroke:#93c5fd
    style HX77G fill:#f0fdf4,stroke:#86efac
    style ORIGIN fill:#f0fdf4,stroke:#86efac
    style S1VM fill:#2563eb,color:#fff
    style S2VM fill:#2563eb,color:#fff
    style S3VM fill:#2563eb,color:#fff
    style A1VM fill:#16a34a,color:#fff
    style A2VM fill:#16a34a,color:#fff
    style A3VM fill:#16a34a,color:#fff
    style A4VM fill:#16a34a,color:#fff
    style A5VM fill:#16a34a,color:#fff
    style PGPRIM fill:#d97706,color:#fff
    style PGSTBY fill:#d97706,color:#fff
    style OP1 fill:#7c3aed,color:#fff
    style OP2 fill:#7c3aed,color:#fff
```



| Node | Physical CPU | Physical RAM | Roles |
| ---- | ------------ | ------------ | ----- |
| node-02 | 12 cores | 31 GB | server + agent |
| node-03 | 16 cores | 31 GB | server + agent |
| node-04 | 16 cores | 31 GB | server + agent |
| node-01 | 16 cores | 32 GB | agent only |
| node-05 | 12 cores | 67 GB | agent only (+ GPU) |
| gpu-workstation | 16 cores | 48 GB | GPU compute VMs only (no K3s agent) — RTX 3060 passthrough (PCI `65:00.0/65:00.1`) + GTX 1080 Ti host display (`17:00.0`) |

Reserve ~2 cores and ~2 GB for the Proxmox host itself. Then split the rest between server VM + agent VM on the dual-role nodes.

Template (Guide 2 current specs): `2 CPU, 2GB RAM, ~2.5GB disk (cloud image size), local-lvm on node-02, VM ID 9000`

K3s clones override to:

- Servers: 4 CPU, 4GB RAM, 40GB disk
- Agents: 6 CPU, 8GB RAM, 80GB disk
- PostgreSQL: 2 CPU, 4GB RAM, 40GB OS + 100GB data disk

## Node Resource Allocation

|            | um560-xt-1       | um773-lite-1     | um773-lite-2     | hx77g-1          | originpc          | ai-1              |
| ---------- | ---------------- | ---------------- | ---------------- | ---------------- | ----------------- | ----------------- |
| Available  | 12core   30gb    | 16core   30gb    | 16core   30gb    | 16core   30gb    | 12core    62gb    | 14core    46gb    |
| Server     | CPU: 4   RAM: 4  | CPU: 4   RAM: 4  | CPU: 4   RAM: 4  |                  |                   |                   |
| Agent      | CPU: 6   RAM: 26 | CPU: 10  RAM: 24 | CPU: 8   RAM: 24 | CPU: 12  RAM: 24 | CPU: 10   RAM: 60 |                   |
| PostgreSQL |                  |                  |                  | CPU: 2   RAM: 4  |                   |                   |
| GPU VMs    |                  |                  |                  |                  |                   | (future AI VMs)   |
