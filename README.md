# 🧱 picto-infra

**picto-infra** is the bare-metal infrastructure stack for hosting all edge Kubernetes workloads on the Dell Edge Server.  
It provides a unified environment for database, monitoring, registry, and cluster management — powering all app stacks.

---

## ⚙️ Overview

This repository defines and manages **host-level infrastructure** — running outside the Kubernetes (K3d) cluster — to provide:
- Persistent data storage (MySQL)
- Local image registry for fast deployments
- System-level metrics (Node Exporter)
- Monitoring stack (Prometheus + Grafana)
- Automated database backups
- Predefined K3d cluster setup and configs

---

## 🧩 Architecture Layout

🖥️ **Dell Edge Host (Bare Metal)**
│
├── 🐳 **Docker (Host Infrastructure Layer)**
│   ├── 🗄️ **MySQL** → Persistent database for all app workloads
│   ├── 🧰 **Local Registry** → On-prem container image store used by K3d clusters
│   ├── 📊 **Node Exporter** → Exposes host system metrics for Prometheus
│   └── ⏰ **Backup Cron Jobs** → Automated MySQL dumps & maintenance
│
└── ☸️ **K3d Cluster (Kubernetes-in-Docker)**
    ├── 📈 **Prometheus** → Scrapes metrics from apps, exporters & host
    ├── 📊 **Grafana** → Visualizes metrics & dashboards
    ├── 📦 **Exporters**
    │   ├── MySQL Exporter → monitors database health
    │   ├── Redis Exporter → monitors in-cluster cache
    │   └── Writer Exporter → tracks data write throughput
    |
    └── ⚙️ **Application Workloads** (apps from other repos)
        ├── edtr
        ├── fmts 
        └── dcms

---

## 🧱 Core Components

| Component | Type | Runs | Purpose |
|------------|------|------|----------|
| **MySQL** | Docker (Compose) | Outside K3d | Persistent database for app services |
| **Registry** | Docker (Compose) | Outside K3d | Local container image registry (port 5000) |
| **Node Exporter** | Docker (Compose) | Outside K3d | Host system metrics |
| **Prometheus** | Kubernetes Deployment | Inside K3d | Cluster & service metrics collection |
| **Grafana** | Kubernetes Deployment | Inside K3d | Metrics dashboard visualization |
| **Exporters** | Kubernetes Deployments | Inside K3d | App-level and DB metrics |
| **Backups** | Host cron job | Outside K3d | Scheduled MySQL dumps |
| **K3d Cluster Config** | YAML + Script | Host | Creates Kubernetes environment for apps |

---

## 🚀 Startup Guide

### 1️⃣ Prerequisites
- Docker & Docker Compose installed  
- Kubectl installed  
- K3d installed
- Helm installed

**Install pre-requisites and host level packages/modules**
```bash
./setup.sh
```
---

### 2️⃣ Start Core Host Infrastructure

**Build and push all containers to registry**
```bash
./docker_build.sh
```
**Run docker container core-services (exclude k8s)**
```bash
./docker_run.sh
```
**Build kubernetes (K3D) infrastructure**
```bash
./k8s_build.sh
```
**Check container-registry images**
```bash
./registry.sh
```
**Destroy all containers/volumes/build/cache/network/clusters (Use with CAUTION)**
```bash
./destroy.sh
```
