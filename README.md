# `kgp` - kubectl get pods (and more)

**Lightning-fast, interactive Kubernetes resource browser powered by fzf**

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-bash-green.svg)](https://www.gnu.org/software/bash/)

## 🚀 Why `kgp`?

**Instant access to your Kubernetes resources.** No loading screens, no bloat, just pure speed.

- ⚡ **Sub-100ms startup** - Launch and start searching immediately
- 🪶 **Minimal footprint** - ~10MB memory usage, just a bash script
- 🎯 **Focused workflow** - Do one thing well: browse and interact with K8s resources
- 🔍 **Fuzzy everything** - Powered by fzf for lightning-fast filtering

## ✨ Features

- **Instant launch** - No initialization, no waiting
- **Interactive browsing** - Pods, containers, deployments, services, configmaps
- **Real-time updates** - Live resource status with smart caching
- **Multi-context aware** - Switch between clusters seamlessly
- **Essential operations** - exec, logs, describe, scale, delete
- **Keyboard-driven** - Optimized for speed with intuitive shortcuts
- **Zero configuration** - Works out of the box with kubectl

## 📦 Installation

### Prerequisites

```bash
kubectl  # Kubernetes CLI
fzf      # Fuzzy finder (>=0.45.0)
```

### Quick Install

```bash
git clone https://github.com/anhpt379/kgp.git
cd kgp
make install
```

## ⚙️ Configuration

### Environment Variables

```bash
export KGP_CACHE_REFRESH=30        # Cache refresh interval (seconds)
export KGP_CACHE_DIR="/tmp/kgp"    # Cache location
export KGP_DEBUG=1                 # Enable debug output
```

## 🙏 Acknowledgments

- [fzf](https://github.com/junegunn/fzf) - The incredible fuzzy finder that powers `kgp`
- [kubectl](https://kubernetes.io/docs/reference/kubectl/) - Kubernetes command-line interface
