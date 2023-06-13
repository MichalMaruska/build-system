
ETC_DIR := /etc
SHAREDIR := /usr/share/build-system/
INSTALL := install
BIN_INSTALL_DIR := /usr/bin

ZSH_COMPLETION_DIR := /usr/share/zsh/vendor-completions/

BINFILES:=$(wildcard bin/*)
SHARED_FILES:=$(wildcard share/*)
COMPLETION_FILES := $(wildcard zsh/Completion/_*)

all:
	echo ""

install: install-zsh install-functions install-configs
	$(INSTALL) -v -D --directory $(DESTDIR)$(BIN_INSTALL_DIR)
	for p in $(BINFILES); do \
	  $(INSTALL) -v -m 555 $$p $(DESTDIR)$(BIN_INSTALL_DIR) ; \
	done

install-configs:
	$(INSTALL) -v -D --directory $(DESTDIR)$(ETC_DIR)/tmpfiles.d
	$(INSTALL) -v -m 444 etc/tmpfiles.d/gbp.conf  $(DESTDIR)$(ETC_DIR)/tmpfiles.d/gbp.conf



install-functions:
	$(INSTALL) -v -D --directory $(DESTDIR)$(SHAREDIR)
	for p in $(SHARED_FILES); do \
	  $(INSTALL) -v -m 444 $$p $(DESTDIR)$(SHAREDIR) ; \
	done


# zsh infrastructure to better use the provided commands!
install-zsh:
	$(INSTALL) -v -D --directory $(DESTDIR)$(ZSH_COMPLETION_DIR)/
	for p in $(COMPLETION_FILES); do \
	  $(INSTALL) -v -m 444 $$p $(DESTDIR)$(ZSH_COMPLETION_DIR) ; \
	done

clean:

git-clean:
	git clean -f -d -x

.PHONY:	install-configs
