VERSION=0.0.1
DESTDIR=
PREFIX=/usr/local
BINDIR=$(PREFIX)/bin
LIBDIR=$(PREFIX)/lib
DOCDIR=$(PREFIX)/doc

all:

install:
	install -m 0755 -d $(DESTDIR)$(LIBDIR)/nila
	install -m 0755 nila.cgi nila_setup_db.pl $(DESTDIR)$(LIBDIR)/nila
	install -m 0755 -d  $(DESTDIR)$(DOCDIR)/nila-$(VERSION)
	install -m 0755 README TODO $(DESTDIR)$(DOCDIR)/nila-$(VERSION)
	install -m 0755 -d $(DESTDIR)$(BINDIR)
	install -m 0755 nila niladsh $(DESTDIR)$(BINDIR)

