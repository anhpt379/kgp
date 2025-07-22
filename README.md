# KZF — Fuzzy finder for Kubernetes pods and containers

KZF is a lightweight CLI tool to **browse, select, and interact with Kubernetes
pods and containers** — powered by [fzf](https://github.com/junegunn/fzf) and
`kubectl`.

## Core Features

* Fuzzy search across pods in your current context/namespace
* Select containers inside pods with instant filtering
* Run common actions: `exec`, `logs`, `describe`, `delete`
* Seamless integration with `kubectl` — no extra config
* Minimal, script-friendly, built for daily workflows

## Why KZF?

If you often switch between pods and containers and want a **fast, interactive
alternative to writing long kubectl commands**, **KZF** helps you do that with
fzf-like speed and simplicity.

## Installation

### Prerequisites

- `kubectl` - Kubernetes command-line tool
- `fzf` - Fuzzy finder
- `bash` 4.0+

### Installation

```bash
git clone https://github.com/anhpt379/kzf.git
cd kzf

make install
```

## Usage

### Basic Usage

```bash
# Launch kzf in current context/namespace
kzf
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
export KZF_CACHE_REFRESH=30

# Log tail lines
export KZF_LOG_TAIL_LINES=100

# Cache directory
export KZF_CACHE_DIR="/tmp/kzf"
```

### Debug Mode

```bash
# Enable debug output
export KZF_DEBUG=1
kzf
```

## Acknowledgments

- [fzf](https://github.com/junegunn/fzf) - The fuzzy finder that powers the UI
- [k9s](https://github.com/derailed/k9s) - Inspiration for Kubernetes TUI tools
