SHELL := /bin/bash

.PHONY: all install timezone tools optional link tmux-plugins clean help

help:
	@echo "make all           - alias for 'make install'"
	@echo "make install       - full setup: timezone + required tools + optional tools + link + tmux plugins"
	@echo "make timezone      - set system timezone to Asia/Singapore"
	@echo "make tools         - install missing required tools (vim tmux fzf curl)"
	@echo "make optional      - install missing optional tools (git make docker python3) + upstream Go + tldr via pipx"
	@echo "make link          - symlink .tmux.conf/.vimrc into \$$HOME and source bash/.workrc from ~/.bashrc"
	@echo "make tmux-plugins  - install TPM and tmux plugins"
	@echo "make clean         - remove symlinks, TPM, and the bashrc source block"

all: install

install:
	@./install.sh all

timezone:
	@./install.sh timezone

tools:
	@./install.sh tools

optional:
	@./install.sh optional

link:
	@./install.sh link

tmux-plugins:
	@./install.sh tmux-plugins

clean:
	@for f in $$HOME/.tmux.conf $$HOME/.vimrc; do \
	  if [ -L "$$f" ]; then echo "removing symlink $$f"; rm -f "$$f"; fi; \
	done
	@if [ -d "$$HOME/.tmux/plugins/tpm" ]; then \
	  echo "removing $$HOME/.tmux/plugins"; \
	  rm -rf "$$HOME/.tmux/plugins"; \
	fi
	@for rc in $$HOME/.profile $$HOME/.bashrc $$HOME/.zshrc $$HOME/.config/fish/config.fish; do \
	  [ -f "$$rc" ] || continue; \
	  removed=0; \
	  if grep -Fq "# >>> dotfiles: source bash/.workrc >>>" "$$rc"; then \
	    echo "removing workrc source block from $$rc"; \
	    sed -i.bak '/# >>> dotfiles: source bash\/\.workrc >>>/,/# <<< dotfiles: source bash\/\.workrc <<</d' "$$rc"; \
	    removed=1; \
	  fi; \
	  if grep -Fq "# >>> dotfiles: PATH additions >>>" "$$rc"; then \
	    echo "removing PATH additions block from $$rc"; \
	    sed -i.bak '/# >>> dotfiles: PATH additions >>>/,/# <<< dotfiles: PATH additions <<</d' "$$rc"; \
	    removed=1; \
	  fi; \
	  if grep -Fq "# >>> dotfiles: fzf init >>>" "$$rc"; then \
	    echo "removing fzf init block from $$rc"; \
	    sed -i.bak '/# >>> dotfiles: fzf init >>>/,/# <<< dotfiles: fzf init <<</d' "$$rc"; \
	    removed=1; \
	  fi; \
	  [ "$$removed" = "1" ] && rm -f "$$rc.bak"; \
	done; \
	exit 0
