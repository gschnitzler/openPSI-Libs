package Tree::Search;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Carp;

use Tree::Iterators qw(array_iterator);
use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(tree_search_position tree_search_deep tree_fraction);

# find the deepest hit, but traverse the keylist backwards until there is a hit, return that hit and the positional keys
# Core::Shell uses this to find subroutines and get an argument list
sub _tree_find_position_it ( $keys, @hits ) {

    # favor the deepest hits
    while ( my $entry = shift @hits ) {

        # actually find out if any of our hits matches the search
        my $array_it = array_iterator( $keys, $entry->[1] );
        my @path     = ();

        while ( my ( $l_elm, $r_elm ) = $array_it->() ) {

            last unless ($r_elm);    # it can be shorter, therefor be undefined

            #say "$l_elm $r_elm";
            if ( $l_elm eq $r_elm ) {
                push @path, $r_elm;
                next;
            }
            @path = ();
            last;
        }

        if ( scalar @path != 0 ) {
            my $args = [ @{$keys}[ $#path + 1 .. $#$keys ] ];
            return $entry->[0], \@path, $args;
        }
    }
    return;
}

# find a match to our keylist
sub _tree_find_it ( $keys, @hits ) {

    my @misses = ();

    # favor the deepest hits
    while ( my $entry = shift @hits ) {

        my $array_it = array_iterator( $keys, $entry->[1] );
        my @path     = ();

        # actually find out if any of our hits matches the search
        while ( my ( $l_elm, $r_elm ) = $array_it->() ) {

            last unless ($l_elm);    # might be a hit

            if ( $r_elm && $l_elm eq $r_elm ) {
                push @path, $r_elm;
                next;
            }

            @misses = (@path) if ( scalar @misses < scalar @path );    # save the deepest miss for debugging
            @path   = ();                                              # drop it
            last;
        }
        return $entry->[0] if (@path);
    }
    return ( '', \@misses );
}

############ frontend #########

# generic search, matches $cond but returns the deepest hit of the keywords (and their positionals)
# $tree is a structure of hashes
# $cond is what will make an entry a hit
# $keys are the 'search keywords' in order
sub tree_search_position ( $tree, $cond, $keys, @args ) {

    my $branches = shift @args;

    confess 'ERROR: no structure given' unless ($tree);
    confess 'ERROR: no condition given' unless ( ref $cond eq 'CODE' );
    confess 'ERROR: no keys given' if ( ref $keys ne 'ARRAY' || scalar $keys->@* == 0 );
    return _tree_find_position_it( $keys, slice_tree( $tree, $cond, $branches, scalar $keys->@* ) );
}

# generic search, matches keys
# $tree is a structure of hashes
# $cond is what will make an entry a hit
# $keys are the 'search keywords' in order
sub tree_search_deep ( $tree, $cond, @args ) {

    my ( $keys, $branches ) = @args;
    $keys = [] unless ($keys);    # might be undefined

    confess 'ERROR: no structure given' unless ($tree);
    confess 'ERROR: no condition given' unless ( ref $cond eq 'CODE' );

    return _tree_find_it( $keys, slice_tree( $tree, $cond, $branches, scalar $keys->@* ) );
}

# i used this so often throughout the codebase, i decided to add it here.
# there are various unclean mutations of this out there (grep for: pop, last, pointer).
# replace them
sub tree_fraction ($p) {

    my $tree    = $p->{tree};
    my @keys    = $p->{keys}->@*;
    my $handler = ( $p->{exception} && ref $p->{exception} eq 'CODE' ) ? $p->{exception} : sub ( $k, @keys ) {
        my $key_string = join( '->', @keys );
        confess "ERROR: key '$k' of sequence '$key_string' not found";
    };

    my ( $pointer, $last_key ) = ( $tree, pop @keys );

    my $check = sub ( $p, $k ) {
        return ( $p->{$k} ) if ( ref $p eq 'HASH' && exists $p->{$k} );
        return $handler->( $k, @keys, $last_key );
    };

    foreach my $key (@keys) {
        $pointer = $check->( $pointer, $key );
        return unless $pointer;
    }

    return unless $check->( $pointer, $last_key );
    return $pointer, $last_key;
}

1;
