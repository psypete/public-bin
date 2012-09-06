
CLASSE="active_server_list.csv"
CLASSE_DATA="merged_server_data.csv"
CLASSE_DATA_MAPFILE="sysadmin_mapping_file.txt"

all: build_generic
	true

build_generic: make_sa_files make_group_report make_server_groups make_groups split_group_lists
	
build_low_group: make_no_vlan_hosts make_no_loaded_nets make_no_loaded_net_csv make_no_lawson_kronos
	make build_generic CLASSE="no_vlan_no_loaded_net.csv" CLASSE_DATA="no_vlan_no_loaded_net.csv"

make_sa_files:
	./serverlist_to_saint.pl $(CLASSE) $(CLASSE_DATA_MAPFILE) ; true

make_group_report:
	make CSV=`pwd`/$(CLASSE_DATA) -C groups make_names
	./make_group_report_csv.sh

make_server_groups:
	./create_server_groups.pl $(CLASSE_DATA) $(CLASSE_DATA_MAPFILE) groups/server_groups.list

make_server_hostlist:
	./get_hostname_list.pl > server_hostlist.txt

split_group_lists:
	make -C groups split_ip_lists

make_groups:
	make CSV=`pwd`/$(CLASSE_DATA) -C groups build_all

make_no_lawson_kronos:
	cat no_vlan_no_loaded_net.csv > tmp1.csv && \
	for NAME in `cat lawson_kronos_exclude.list` ; do \
		cat tmp1.csv | csvgrep.pl -v -n ServerName "$$NAME" > tmp2.csv && \
		/bin/mv tmp2.csv tmp1.csv ; \
	done && \
	/bin/mv tmp1.csv no_vlan_no_loaded_net.csv

make_no_vlan_hosts:
	(head -1 $(CLASSE_DATA); cat groups/hosts_in_*_group.list) | ./print_non_virtual_lan_hosts.sh | tail -n +2 | sort -u | (head -1 $(CLASSE_DATA) ; cat) > all_non_vlan_group_hosts.csv

make_no_loaded_nets:
	cat groups/ips_in_*_group.list > all_group_ips.list
	../scripts/is_ip_in_range.pl `cat loaded_network_segments.txt | grep '\.' | sed -e 's/ /\//g; s/^/-r /;' | xargs` -f all_group_ips.list | awk '{print $$1}' | sort -u > no_loaded_nets_ips.list

make_no_loaded_net_csv: all_non_vlan_group_hosts.csv
	./print_non_loaded_network_segments.pl all_non_vlan_group_hosts.csv no_loaded_nets_ips.list | (head -1 all_non_vlan_group_hosts.csv ; cat ) > no_vlan_no_loaded_net.csv

clean:
	/bin/rm sysadmins/* building/* all_non_vlan_group_hosts.csv all_group_ips.list no_loaded_nets_ips.list no_vlan_no_loaded_net.csv ; \
	make -C groups clean

