#!/usr/bin/perl
use strict;

# Package

use Net::LDAP;

# Initializing

my ($ldap, $mesg);
my $ldap = Net::LDAP->new ( "ops253" ) or die "$@";

# Binding

$mesg = $ldap->bind ( version => 3 );          # use for searches
#$mesg = $ldap->bind ( "$userToAuthenticate",           
#                       password => "$passwd",
#                       version => 3 );          # use for changes/edits
$mesg = $ldap->bind; # anonymous bind

# see your LDAP administrator for information concerning the
# user authentication setup at your site.

# Operation - generating a Search

sub LDAPsearch {
	my ($ldap,$searchString,$attrs,$base) = @_;

	# if they don't pass a base... set it for them

	if (!$base ) { $base = "ou=legacy,svc=idb"; }

	# if they don't pass an array of attributes...
	# set up something for them

	if (!$attrs ) { $attrs = [ 'cn','mail' ]; }

	my $result = $ldap->search ( base    => "$base",
                                scope   => "sub",
                                filter  => "$searchString",
                                attrs   =>  $attrs
                              );

}

my @Attrs = ( );               # request all available attributes
                               # to be returned.

#my $result = LDAPsearch ( $ldap, "objectclass=*", \@Attrs );
my $result = LDAPsearch ( $ldap, '(!(&(os=FC3)(conftag=PREVIEW)))', \@Attrs );


# Processing

my $href = $result->as_struct;

my @arrayOfDNs  = keys %$href;        # use DN hashes

foreach ( @arrayOfDNs ) {
   print $_, "\n";
   my $valref = $$href{$_};

   # get an array of the attribute names
   # passed for this one DN.
   my @arrayOfAttrs = sort keys %$valref; #use Attr hashes

   my $attrName;        
   foreach $attrName (@arrayOfAttrs) {

     # skip any binary data: yuck!
     if ( $attrName =~ /;binary$/ ) {
       next;
     }

     my $attrVal =  @$valref{$attrName};
     print "\t $attrName: @$attrVal \n";
   }
   print "#-------------------------------\n";
}


# #------------
# #
# # handle each of the results independently
# # ... i.e. using the walk through method
# #
# my @entries = $result->entries;
#
# my $entr;
# foreach $entr ( @entries ) {
#   print "DN: ", $entr->dn, "\n";
#
#   foreach my $attr ( sort $entr->attributes ) {
#     # skip binary we can't handle
#     next if ( $attr =~ /;binary$/ );
#     print "  $attr : ", $entr->get_value ( $attr ) ,"\n";
#   }
#
#   print "#-------------------------------\n";
# }


