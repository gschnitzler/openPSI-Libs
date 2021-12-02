package Core::Query;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Carp;

use Tree::Merge qw(query_tree);

# Export
our @EXPORT_OK = qw(query);

sub _query ( $current_ref, $keys, $param ) {

    my @left_elements = $keys->@*;

    while ( my $key = shift @left_elements ) {

        # if we hit a CODE object (state), we evaluate that CODE and pass it along the left elements
        # state code therefor has to support argument handling (or die if arguments are supplied)
        if ( ref $current_ref eq 'CODE' ) {
            return $current_ref->( $key, @left_elements );
        }

        if ( ref $current_ref eq 'HASH' && exists $current_ref->{$key} ) {
            $current_ref = $current_ref->{$key};
            next;
        }
        my $error = join( '', 'request: \'', join( ' ', $keys->@* ), '\', not found: \'', join( ' ', $key, @left_elements ), '\'. ' );
        return ( '0', $error );
    }

    if ( ref $current_ref eq 'CODE' ) {

        # here it gets dirty
        # when a CODE ref is encountered while there are still arguments left, that code is executed with the remaining arguments
        # this is what happens in the while loop
        # now, some state handlers require more than keywords, such as a hashref.

        return $current_ref->() unless ($param);
        return $current_ref->($param);
    }
    else {
        return $current_ref;
    }
    return;
}

###############################################
# Frontend Functions

sub query ($data) {

    return sub (@args) {

        my $keys       = shift @args;
        my $param      = shift @args;
        my @split_keys = ();

        @split_keys = split( ' ', $keys ) if ($keys);

        my ( $result, $failed ) = _query( $data, [@split_keys], $param );

        confess "ERROR: queried too deep or data not found: $failed " if ($failed);

        # scalar data can not be messed with
        return $result unless ( ref $result );

        # $data stored in a query should be immutable.
        # don't let Modules mess up their data by accident
        # there should be an update() function though that lets you change data on purpose
        # now we resolv remaining CODE in $result, that was nested deeper than @query
        # dclone cant be used - its not designed to handle CODE.
        # same with hash merge. therefor, i designed clone_tree
        return query_tree $result

    };
}

1;
