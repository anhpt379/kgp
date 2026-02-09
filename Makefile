ifeq ($(shell id -u),0)
	INSTALL_BIN_DIR ?= /usr/local/bin
	INSTALL_LIB_DIR ?= /usr/local/lib/kgp
else
	INSTALL_BIN_DIR ?= $(HOME)/.local/bin
	INSTALL_LIB_DIR ?= $(HOME)/.local/lib/kgp
endif

LIB_SCRIPTS := $(wildcard lib/*.sh)
LIB_BINS := lib/format-pods.py

.PHONY: all install uninstall clean test test-verbose test-python test-all

all: install

install:
	@echo "Installing kgp to $(INSTALL_BIN_DIR)..."
	install -Dm755 kgp $(INSTALL_BIN_DIR)/kgp
	@echo "Installing libraries to $(INSTALL_LIB_DIR)..."
	install -d $(INSTALL_LIB_DIR)
	@for lib in $(LIB_SCRIPTS); do \
		echo "  Installing $$lib..."; \
		install -m755 $$lib $(INSTALL_LIB_DIR)/$$(basename $$lib); \
	done
	@for bin in $(LIB_BINS); do \
		echo "  Installing $$bin..."; \
		install -m755 $$bin $(INSTALL_LIB_DIR)/$$(basename $$bin); \
	done
	@echo "Installation complete!"

uninstall:
	@echo "Uninstalling kgp..."
	rm -f $(INSTALL_BIN_DIR)/kgp
	rm -rf $(INSTALL_LIB_DIR)
	@echo "Uninstall complete!"

test:
	@command -v bats >/dev/null 2>&1 || { echo "Error: bats is not installed. Install with: dnf install bats"; exit 1; }
	@bats tests/*.bats

test-verbose:
	@command -v bats >/dev/null 2>&1 || { echo "Error: bats is not installed. Install with: dnf install bats"; exit 1; }
	@bats --verbose-run tests/*.bats

test-python:
	@command -v pytest >/dev/null 2>&1 || { echo "Error: pytest is not installed. Install with: pip install pytest"; exit 1; }
	@pytest tests/test_format_pods.py -v

test-all: test test-python
