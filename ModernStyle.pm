# This is basically Modern::Perl with added subroutine signatures
package ModernStyle;

use v5.36;
use strict;
use mro     ();
use feature ();

#####################################################################
## This could be used to inject a subroutine into the caller
## It seemed saner to import kexit as a module
#use Carp;    # used by kexists
#our @ISA    = qw(Exporter);    # inherit from Exporter
#our @EXPORT = qw(kexists);     # pollute caller namespace with this
## use this in import()
# ModernStyle->export_to_level( 1, @_ );    # EXPORT using Exporter without its import method, which can't be used here...
######################################################################
sub import {

    my ($class) = @_;
    warnings->import;
    strict->import;
    feature->import( ':5.36' );
    #warnings->unimport('experimental::signatures');
    mro::set_mro( scalar caller(), 'c3' );
    return;
}

sub unimport {    ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    warnings->unimport;
    strict->unimport;
    feature->unimport;
    return;
}

1;

