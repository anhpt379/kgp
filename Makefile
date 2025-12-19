ifeq ($(shell id -u),0)
	INSTALL_BIN_DIR ?= /usr/local/bin
	INSTALL_LIB_DIR ?= /usr/local/lib/kgp
else
	INSTALL_BIN_DIR ?= $(HOME)/.local/bin
	INSTALL_LIB_DIR ?= $(HOME)/.local/lib/kgp
endif

LIB_SCRIPTS := $(wildcard lib/*.sh)
LIB_BINS := lib/format-pods.py

.PHONY: all install uninstall clean

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
