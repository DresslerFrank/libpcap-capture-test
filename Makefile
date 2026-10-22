PKG_CONFIG ?= pkg-config
CFLAGS ?= -Wall -Wextra

LIBPCAP_CFLAGS = $(shell $(PKG_CONFIG) --cflags libpcap)
LIBPCAP_LIBS = $(shell $(PKG_CONFIG) --libs libpcap)

.PHONY: check clean

capture: capture.c
	$(PKG_CONFIG) --exists libpcap
	$(CC) $(CPPFLAGS) $(CFLAGS) $(LIBPCAP_CFLAGS) -o $@ $< $(LDFLAGS) $(LIBPCAP_LIBS)

check:
	shellcheck -- *.sh
	autopep8 --indent-size 2 --diff --exit-code -- *.py

clean:
	rm -f capture
