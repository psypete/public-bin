

all: extract_nmap_certs make_text_certs extract_cacerts make_text_ca_certs is_cert_valid

nmap:
	@echo "Running Nmap"
	nmap -sT -sV -p 443 -O -v -v -n -iL nmapiplist.txt -Pn --script ssl-cert,ssl-google-cert-catalog --min-parallelism 100 --min-hostgroup 100 -oA nmap-scan-ip-list-ssl

extract_nmap_certs:
	@echo "Extracting PEM certs from nmap output"
	mkdir certs
	for file in *.nmap ; do ./extract_pem_certs.pl $$file certs ; done

make_text_certs:
	@echo "Making text version of PEM certificates"
	for file in `file certs/* | grep 'PEM certificate' | cut -d : -f 1` ; do \
		openssl x509 -noout -text -in $$file > $$file.txt ; \
	done ; true

extract_cacerts:
	@echo "Extracting CA certs from curl file"
	mkdir ca-certs
	./extract_pem_certs.pl cacert.pem ca-certs

make_text_ca_certs:
	@echo "Making text version of PEM CA certificates"
	mkdir ca-certs-txt
	for file in `file ca-certs/* | grep 'PEM certificate' | cut -d : -f 1` ; do \
	    FN=`basename $$file` ; \
	    openssl x509 -noout -text -in $$file > ca-certs-txt/$$FN ; \
	done ; true

is_self_signed_perl:
	./is_self_signed.pl | tee is_self_signed.log

is_self_signed:
	@NOWSEC=`date +%s` ; \
	for file in certs/*.txt ; do \
		SUBJECT=`grep Subject: $$file | sed -e 's/^.*Subject: //'` ; \
		ISSUER=`grep Issuer: $$file | sed -e 's/^.*Issuer: //'` ; \
		NOTAFTER=`grep 'Not After :' $$file | sed -e 's/^.*Not After : //'` ; \
		NOTAFTERSEC=`date -d "$$NOTAFTER" +%s` ; \
		if [ "$$SUBJECT" = "$$ISSUER" ] ; then \
			echo "CERT $$file is self-signed" ; \
		elif echo "$$SUBJECT" | perl -lne'if(/CN=([a-z0-9-\.]+)/i){$$_=$$1;s/\.$$//g;if (/^.*[a-z].*$$/i){$$o=$$_;$$r=s/\.//g;exit 0 if $$r >= 2}};exit 1' ; then \
			echo "CERT $$file might not be self signed" ; \
		fi ; \
		if [ $$NOTAFTERSEC -le $$NOWSEC ] ; then \
			echo "CERT $$file has expired" ; \
		fi ; \
	done ; true

is_cert_valid:
	for cert in certs/*.txt ; do ./is_certificate_trusted.pl $$cert ./ca-certs-txt/ ; if [ $$? -ne 0 ] ; then echo "$$cert not valid" ; else echo "$$cert is valid" ; fi ; done | tee is_cert_valid.log

report:
	@echo -en "Total records: " ; tail -n +2 certificates_by_domain.csv | wc -l ; \
	echo -en "Total unique records: " ; sort -u certificates_by_domain.csv | wc -l ; \
	echo -en "Unique Common Names: " ; csvcut.pl -n "Common Name" -f certificates_by_domain.csv -r | sort -u | wc -l ; \
	echo -en "Unique Subject Alternate Names: " ; csvcut.pl -n "Subject Alternate Name" -f certificates_by_domain.csv -r | sort -u | wc -l ; \
	echo -en "Expired: " ; csvgrep.pl -f certificates_by_domain.csv -n Expired "1" -r | tail -n +2 | wc -l ; \
	echo -en "Expiring this year: " ; csvgrep.pl -f certificates_by_domain.csv -n "Expiration Date" "(Sep|Oct|Nov|Dec).+2012" -r | wc -l ; \
	echo -en "Trusted/Valid: " ; csvgrep.pl -f certificates_by_domain.csv -n Trusted "1" -r | tail -n +2 | wc -l ; \
	echo -en "Non-expired Trusted Domains with Wildcards: " ; csvgrep.pl -f certificates_by_domain.csv -n "Common Name" "\*" | csvgrep.pl -n "Expired" "0" | csvgrep.pl -n Trusted 1 | tail -n +2 | wc -l ; \
	echo "Five most common duplicate records: " ; cat certificates_by_domain.csv | sort | uniq -c | sort -g | tail -n 5 ; \
	echo "Ten most common Common Names: " ; cat certificates_by_domain.csv | csvcut.pl -n "Common Name" -r | sort | uniq -c | sort -g | tail -n 10

clean:
	/bin/rm certs/* ca-certs/* ca-certs-txt/* is_cert_valid.log is_self_signed.log
	/bin/rmdir certs ca-certs ca-certs-txt

