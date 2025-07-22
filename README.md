# KGP — Fuzzy finder for Kubernetes pods and containers

KGP is a lightweight CLI tool to **browse, select, and interact with Kubernetes
pods and containers** — powered by [fzf](https://github.com/junegunn/fzf) and
`kubectl`.

## Core Features

* Fuzzy search across pods in your current context/namespace
* Select containers inside pods with instant filtering
* Run common actions: `exec`, `logs`, `describe`, `delete`
* Seamless integration with `kubectl` — no extra config
* Minimal, script-friendly, built for daily workflows

## Why KGP?

If you often switch between pods and containers and want a **fast, interactive
alternative to writing long kubectl commands**, **KGP** helps you do that with
fzf-like speed and simplicity.

## Installation

### Prerequisites

- `kubectl` - Kubernetes command-line tool
- `fzf` - Fuzzy finder
- `bash` 4.0+

### Installation

```bash
git clone https://github.com/anhpt379/kgp.git
cd kgp

make install
```

## Usage

### Basic Usage

```bash
# Launch kgp in current context/namespace
kgp
```

### Navigation

**Pod View:**
- Type to filter pods
- `ENTER` - View containers in selected pod
- `CTRL-E` - Execute shell into pod
- `CTRL-D` - Describe pod
- `CTRL-K` - Delete pod
- `CTRL-Y` - Copy pod name to clipboard
- `CTRL-R` - Refresh data
- `CTRL-Q` - Quit

**Container View:**
- Type to filter containers
- `ENTER` - View container logs
- `CTRL-E` - Execute shell into container
- `CTRL-D` - Describe container
- `CTRL-Y` - Copy container name to clipboard
- `ESC` - Return to pod view
- `CTRL-Q` - Quit

## Configuration

### Environment Variables

```bash
# Cache refresh interval (seconds)
export KGP_CACHE_REFRESH=30

# Log tail lines
export KGP_LOG_TAIL_LINES=100

# Cache directory
export KGP_CACHE_DIR="/tmp/kgp"
```

### Debug Mode

```bash
# Enable debug output
export KGP_DEBUG=1
kgp
```

## Acknowledgments

- [fzf](https://github.com/junegunn/fzf) - The fuzzy finder that powers the UI
- [k9s](https://github.com/derailed/k9s) - Inspiration for Kubernetes TUI tools
