
all: build_all
	true

build_all: make_lists make_names
	true

make_lists:
	./make_lists.sh $(CSV) server_groups.list

make_names: names.map
	[ -e names.map ] || ./map_names.pl

names.map: names.map

split_ip_lists:
	for list in ips_in_*_group.list ; do split -l 200 -d $$list split_$$list. ; done

clean:
	/bin/rm names.map ; \
    /bin/rm split_*.list.* *.list ; \
	/bin/rm server_groups.list || true

