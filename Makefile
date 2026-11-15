# SPDX-License-Identifier: GPL-3.0-or-later
#
# Convenience wrapper. The real logic lives in install.sh / uninstall.sh.

PREFIX ?= /usr/local
SHELL  := /bin/bash

.PHONY: help install uninstall test lint check dist

help:
	@echo "targets:"
	@echo "  install     install to \$$PREFIX (default $(PREFIX)), needs root"
	@echo "  uninstall   remove installed files"
	@echo "  test        run the test suite (no hardware needed)"
	@echo "  lint        shellcheck + python/bash syntax checks"
	@echo "  check       lint + test"

install:
	./install.sh --prefix $(PREFIX)

uninstall:
	./uninstall.sh

lint:
	shellcheck -S warning install.sh uninstall.sh src/pendrive-vault-helper tests/*.sh
	bash -n install.sh uninstall.sh src/pendrive-vault-helper tests/*.sh
	python3 -m py_compile src/pendrive-vault src/pendrive-vault-token
	@echo "lint ok"

test:
	./tests/test-token-driver.sh
	./tests/test-helper-guards.sh

check: lint test

dist:
	@echo "packaging/ holds the AUR recipe (pendrive-vault-git)"
