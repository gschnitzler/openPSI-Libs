package Tree::Keys;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(query_keys serialize_keys);

Readonly my $TYPE_PADDING => 8;

sub query_keys ($struct) {

    my @paths    = ();
    my $key_tree = {};
    my @slices   = slice_tree( $struct, sub { return 1 } );

    foreach my $entry (@slices) {

        my $path = $entry->[1];
        my $ref  = ref( $entry->[0] );

        $ref = 'SCALAR' unless ($ref);
        next if ( $ref eq 'HASH' && scalar keys $entry->[0]->%* != 0 );

        # the $path anonymous hash is needed to copy the data, otherwise the later pop will remove the last entry because it is a reference
        push @paths, [ [ $path->@* ], $ref ];

        my $current      = $key_tree;
        my $last_element = pop $path->@*;

        foreach my $key ( $path->@* ) {
            $current->{$key} = {} unless exists( $current->{$key} );
            $current = $current->{$key};
        }
        $current->{$last_element} = $ref;
    }

    return ( \@paths, $key_tree );
}

# used to visualize structures, like Data::Dumper, but without content
# accepts the \@paths of query_keys as input
sub serialize_keys ( $paths ) {

    my @list      = ();
    my $serialize = sub ($e) {

        my @unsorted = ();
        foreach my $path ( $e->@* ) {
            push @unsorted, join( ',', join( ' ', $path->[0]->@* ), $path->[1] );    # join and later split is used for easy sorting.
        }
        return @unsorted;
    };

    # output a path list
    foreach my $entry ( sort $serialize->($paths) ) {

        my @parts  = split( /,/, $entry );
        my $type   = $parts[1];
        my $line   = $parts[0];
        my $length = length $type;

        $type .= ' ' for ( $length .. $TYPE_PADDING );    # pad string
        push @list, "$type, $line";
    }
    return @list;
}
1;
