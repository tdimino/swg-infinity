PREFIX ?= $(HOME)/bin
COMP_DIR ?= $(HOME)/.zsh/completions

.PHONY: install uninstall

install:
	@mkdir -p $(PREFIX)
	@ln -sf $(CURDIR)/bin/swg $(PREFIX)/swg
	@echo "Linked: $(PREFIX)/swg → $(CURDIR)/bin/swg"
	@if [ -d "$(COMP_DIR)" ]; then \
		ln -sf $(CURDIR)/completions/swg.zsh $(COMP_DIR)/_swg; \
		echo "Linked: $(COMP_DIR)/_swg → $(CURDIR)/completions/swg.zsh"; \
	else \
		echo "Note: $(COMP_DIR) not found — skipping zsh completions"; \
	fi

uninstall:
	@rm -f $(PREFIX)/swg
	@echo "Removed: $(PREFIX)/swg"
	@rm -f $(COMP_DIR)/_swg 2>/dev/null || true
	@echo "Removed: $(COMP_DIR)/_swg"
