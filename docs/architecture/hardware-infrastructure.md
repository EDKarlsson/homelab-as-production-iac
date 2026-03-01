# Hardware Infrastructure

## Physical Network Topology

```mermaid
graph TD
    INT["Internet\n(Google Fiber 2 GbE)"]
    GW["GFiber Modem + Cloud Gateway Fiber\nUniFi · 10 GbE uplink"]
    XG["USW Flex XG\n4x 10 GbE"]
    SW["USW 16 PoE\n16x 1 GbE"]
    NAS["Synology NAS\n10.0.0.161\nNFS storage"]

    INT --> GW
    GW --> XG
    XG --> SW
    XG -->|"2.5 GbE"| UM560["node-02\n10.0.0.10\n2.5 GbE NIC"]
    XG -->|"2.5 GbE"| HX77G["node-01\n10.0.0.13\n2.5 GbE NIC"]
    SW -->|"1 GbE"| UM773A["node-03\n10.0.0.11\n2.5 GbE NIC"]
    SW -->|"1 GbE"| UM773B["node-04\n10.0.0.12\n2.5 GbE NIC"]
    SW -->|"1 GbE"| ORIGIN["node-05\n10.0.0.14\n1 GbE NIC"]
    SW -->|"1 GbE"| AI1["gpu-workstation (standalone)\n10.0.0.15\n1 GbE NIC"]
    SW -->|"1 GbE"| NAS

    style INT fill:#6b7280,color:#fff
    style GW fill:#1d4ed8,color:#fff
    style XG fill:#1e40af,color:#fff
    style SW fill:#1e3a8a,color:#fff
    style NAS fill:#92400e,color:#fff
    style AI1 fill:#6b7280,color:#fff,stroke-dasharray:5
```

## Proxmox Cluster Topology

```mermaid
graph TD
    subgraph K3S["K3s Cluster — homelab"]
        subgraph CTRL["Control Plane (3 servers)"]
            S1["k3s-server-1\n4 CPU · 4 GB\n@ node-02"]
            S2["k3s-server-2\n4 CPU · 4 GB\n@ node-03"]
            S3["k3s-server-3\n4 CPU · 4 GB\n@ node-04"]
        end
        subgraph AGENTS["Workers (5 agents)"]
            A1["k3s-agent-1\n6 CPU · 26 GB\n@ node-02"]
            A2["k3s-agent-2\n10 CPU · 24 GB\n@ node-03"]
            A3["k3s-agent-3\n8 CPU · 24 GB\n@ node-04"]
            A4["k3s-agent-4\n12 CPU · 24 GB\n@ node-01"]
            A5["k3s-agent-5\n10 CPU · 60 GB\n@ node-05"]
        end
    end

    PG["PostgreSQL HA\nVIP: 10.0.0.44\n@ node-01 + node-05"]
    OP["1Password Connect HA\nVIP: 10.0.0.72\n@ node-01 + node-05 (LXC)"]

    S1 & S2 & S3 -->|"external datastore"| PG
    S1 & S2 & S3 -->|"leader election"| S1

    style CTRL fill:#eff6ff,stroke:#93c5fd
    style AGENTS fill:#f0fdf4,stroke:#86efac
    style PG fill:#fef3c7,stroke:#fbbf24
    style OP fill:#fdf4ff,stroke:#e879f9
```

## Computers

| Model      | Vendor     | Cluster | CPU Model      | Cores/CPUs  | Ram   | GPU         | Type       | vRam | Network IC | Disk #1   | Disk #2  | Disk #3   | Disk #4 | Disk #5 |
| ---------- | ---------- | ------- | -------------- |:-----------:| ----- | ----------- | ---------- |:----:|:----------:| --------- | -------- | --------- | ------- | ------- |
| UM560 XT   | Minisforum | Yes     | Ryzen 5 5600H  | 6 / 12      | 32GiB | Radeon      | Integrated | N/A  | 2.5Gbps    | 512GB SSD |          |           |         |         |
| UM773 Lite | Minisforum | Yes     | Ryzen 7 7735HS | 8 / 16      | 32GiB | Radeon 680M | Integrated | N/A  | 2.5Gbps    | 1TB NVMe  |          |           |         |         |
| UM773 Lite | Minisforum | Yes     | Ryzen 7 7735HS | 8 / 16      | 32GiB | Radeon 680M | Integrated | N/A  | 2.5Gbps    | 1TB NVMe  |          |           |         |         |
| HX77G      | Minisforum | Yes     | Ryzen 7 7735HS | 8 / 16      | 32GiB | RX 6600M    | Dedicated  | 8GB  | 2.5Gbps    | 1TB NVMe  |          |           |         |         |
| NS-17      | Origin PC  | Yes     | i7-8700K       | 6 / 12      | 64GiB | GTX 1080    | Dedicated  | 8GB  | 1 Gbps     | 2TB NVMe  | 2TB NVMe | 500GB HDD | 2TB HDD |         |
| Custom     | DIY        | Yes (gpu-workstation) | i7-7820X  | 8 / 16      | 48GiB | RTX 3060    | Dedicated  | 8GB  | 1 Gbps     | 2TB NVMe  | 4TB SSD  | 250GB SSD | 4TB SSD | 1TB SSD |

## Networking

| Model               | Vendor | Downlink | WLAN Ports | 10GbE | 2.5GbE | 1GbE |
| ------------------- | ------ | -------- | ---------- | ----- | ------ | ---- |
| GFiber Modem        | Google | 2 GbE    | 1x2 GbE    | 1     | 0      |      |
| Cloud Gateway Fiber | UniFi  | N/A      | 2x10 GbE   | 1     | 4      |      |
| USW Flex XG         | UniFI  | N/A      | 2x10 GbE   | 4     |        | 1    |
| USW 16 PoE          | UniFI  | N/A      | 0          | 0     |        | 16   |

## Storage
