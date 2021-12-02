package InVivo;

use ModernStyle;
use Exporter qw(import);
use Carp;

our @EXPORT_OK = qw(kexists kdelete);

#################################################################################################################
# nested references get autovivified in perl. Really whenever you reference nested structures of any kind.
# Counterintuitively, using exists() or delete() on nested hashes also autovivifies said hashes (except for the last element).
# By the simple act of passing nested references. Which, as everywhere else, are dereferenced before passing.
# Its one of those 'Oh my, perl' gotchas.
# Perls own solution would be to check every key in a cascade. every. fucking. time.
# And also to remember to do so. every. fucking. time.
# Needless to say, I got bitten by that many times over. Only to forget about it in the next burst hacking session.
# There is a 'autovivification' Module on CPAN for the sole purpose of circumventing this behavior.
# However, its thousands of lines of XS. So, no.
#################################################################################################################

sub kexists ( $t, @keys ) {

    confess 'ERROR: not a reference' unless ref $t;
    my $h = $t;
    for my $k (@keys) {
        confess 'ERROR: undefined key' unless defined $k;
        return undef unless exists $h->{$k};
        $h = $h->{$k};
    }
    return $h;
}

sub kdelete ( $t, @keys ) {

    confess 'ERROR: not a reference' unless ref $t;
    confess 'ERROR: no keys' if scalar @keys == 0;

    my $h        = $t;
    my $last_key = pop @keys;
    for my $k (@keys) {
        confess 'ERROR: undefined key' unless defined $k;
        return undef unless exists $h->{$k};
        $h = $h->{$k};
    }

    return exists( $h->{$last_key} ) ? delete $h->{$last_key} : undef;
}

__END__

use InVivo qw(kdelete kexists);
my $h = {};
print 'if exists: ',                       Dumper $h if exists $h->{a}->{b}->{c}->{v};    # does not print
print 'delete (undef): ',                  Dumper delete $h->{d}->{e}->{f}->{v};
print 'a and d after exists and delete: ', Dumper $h;
print 'kexists (empty hash): ',                  Dumper kexists( $h, 'a', 'b', 'c' );
print 'kexists does not add anything (undef): ', Dumper kexists( $h, 'x', 'b', 'c' );
print 'kdelete removes a (empty hash): ',        Dumper kdelete( $h, 'a', 'b', 'c' );
print 'kdelete does not add anything (undef): ', Dumper kdelete( $h, 'x', 'b', 'c' );
print 'contains only a->b and d->e->f: ',        Dumper $h;
