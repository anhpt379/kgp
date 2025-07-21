ifeq ($(shell id -u),0)
	INSTALL_BIN_DIR ?= /usr/local/bin
	INSTALL_LIB_DIR ?= /usr/local/lib/kselect
else
	INSTALL_BIN_DIR ?= $(HOME)/.local/bin
	INSTALL_LIB_DIR ?= $(HOME)/.local/lib/kselect
endif

.PHONY: all install uninstall

all: install

install:
	install -Dm755 kselect $(INSTALL_BIN_DIR)/kselect
	install -d $(INSTALL_LIB_DIR)
	install -m755 lib/build-pod-container-tables $(INSTALL_LIB_DIR)/build-pod-container-tables

uninstall:
	rm -f $(INSTALL_BIN_DIR)/kselect
	rm -rf $(INSTALL_LIB_DIR)
