All of the stuff in this directory works.

Useful scripts:

 * csv_report_of_certs.pl       - Given a list of certificates, prints a CSV
                                  report summarizing them (including whether
                                  a cert is trusted, based on log output from
                                  the is_certificate_trusted.pl script)

 * extract_pem_certs.pl         - Finds PEM certificates in a file and writes
                                  them to individual files. Useful on Nmap scan
                                  results and cacert.pem (list of public root
                                  certificate authorities' PEM files)
 
 * is_certificate_trusted.pl    - Given a certificate and a directory full of
                                  root CA certificates, traces the chain of
                                  trust to find if the certificate was signed by
                                  a trusted root CA. Errors out if the
                                  certificate was not signed by a trusted CA or
                                  if it is self-signed.

 * is_self_signed.pl            - Does a basic check to see if a certificate is
                                  self-signed.

