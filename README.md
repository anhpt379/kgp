# kselect

A lightweight, fast Kubernetes pod and container manager with fuzzy finding
capabilities. Built as a faster alternative to k9s for quick pod operations and
log viewing.

## Features

- **Fast fuzzy search** - Powered by fzf for lightning-fast filtering
- **Hierarchical navigation** - Browse pods → containers → logs seamlessly
- **Real-time updates** - Background cache refresh keeps data current
- **Essential operations** - Exec, describe, delete, logs with keyboard shortcuts
- **Lightweight** - Minimal dependencies, fast startup
- **Context aware** - Respects your current kubectl context and namespace

## Installation

### Prerequisites

- `kubectl` - Kubernetes command-line tool
- `fzf` - Fuzzy finder
- `jq` - JSON processor
- `bash` 4.0+

### Installation

```bash
git clone https://github.com/anhpt379/kselect.git
cd kselect

make install
```

## Usage

### Basic Usage

```bash
# Launch kselect in current context/namespace
kselect
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
export KSELECT_CACHE_REFRESH=30

# Log tail lines
export KSELECT_LOG_TAIL_LINES=100

# Cache directory
export KSELECT_CACHE_DIR="/tmp/kselect"
```

### Debug Mode

```bash
# Enable debug output
export KSELECT_DEBUG=1
kselect
```

## Acknowledgments

- [fzf](https://github.com/junegunn/fzf) - The fuzzy finder that powers the UI
- [k9s](https://github.com/derailed/k9s) - Inspiration for Kubernetes TUI tools
