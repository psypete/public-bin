
DESTDIR=
PREFIX=/usr

all:

install: simplecfm.1.gz
	install -m 0755 -d $(DESTDIR)$(PREFIX)/man/man1
	install -m 0644 simplecfm.1.gz $(DESTDIR)$(PREFIX)/man/man1/simplecfm.1.gz
	install -m 0755 -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 simplecfm $(DESTDIR)$(PREFIX)/bin/simplecfm

clean:
	rm simplecfm.1.gz simplecfm.1

simplecfm.1.gz:
	pod2man simplecfm > simplecfm.1
	gzip -9 simplecfm.1
