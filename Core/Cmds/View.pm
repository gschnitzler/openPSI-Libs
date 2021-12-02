package Core::Cmds::View;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Search qw(tree_search_position tree_search_deep);

# Export
our @EXPORT_OK = qw(import_view);

#
# this module provides insights into the DATA part of a particular command.
# usefull to trace bugs relating wrong assumptions about data.
# this module is old and full of little quirks, but performs well enough
# state variables where introduced long after this, so it lacks the capability to resolve CODE refrences
##########################################################################################

sub _query ( $data, @keys ) {

    unless (@keys) {
        say 'no keys given.';
        return;
    }

    my $cond = sub ($branch) {
        return 1 if ref $branch->[0] eq 'HASH' && exists $branch->[0]->{DATA} && ref $branch->[0]->{DATA} eq 'CODE';
        return;
    };

    # add 'cmds' to key list to resemble the $core structure, thus other data (like id or config) is not accessible
    return tree_search_position( $data, $cond, \@keys );

}

sub _query_wrapper ( $query, $args ) {

    # we get all the data, so we avoid die if data is not found;
    my $result = $query->();

    return $result unless ( $args->[0] );

    my ( $hit, $misses ) = tree_search_deep( $result, sub { return 1; }, $args );

    #  say Dumper $hit, $misses;
    say 'queried too deep or data not found, structure ended after: ', join( ' ', $misses->@* ) if $misses;
    return $hit;
}

sub view ( $data, @keys ) {

    my ( $query, $path, $args ) = _query( $data->{cmds}, @keys );

    unless ($query) {
        say 'data not found';
        return;
    }

    my $result = _query_wrapper( $query->{DATA}, $args );

    $Data::Dumper::Indent = 1;
    $Data::Dumper::Terse  = 1;

    say Dumper $result if ($result);

    return;
}

sub list_keys ( $data, @keys ) {

    my ( $query, $path, $args ) = _query( $data->{cmds}, @keys );

    unless ($query) {
        say 'data not found';
        return;
    }

    # normal query interface
    my $result = _query_wrapper( $query->{DATA}, $args );

    unless ($result) {
        say 'data not found';
        return;
    }

    if ( ref $result ne 'HASH' ) {
        say 'ERROR: queried too deep, not a hash reference.';
        return;

    }
    say foreach ( keys $result->%* );

    return;
}

###############################################
# Frontend Functions

sub import_view ($core) {

    my $struct = {
        view => {
            CMD => sub (@args) {

                shift @args;    # contains $query
                view( $core, @args );
            },
            DESC => 'Prints a commands data tree.',
            HELP => [
                'usage:', 'use \'help\' to get a command overview, then type',
                '', 'view <full cmd> [args]',
                '',
                'to query a commands dataset.',
            ],
            DATA => {}
        },
        keys => {
            CMD => sub(@args) {
                shift @args;    # contains $query
                list_keys( $core, @args );
            },
            DESC => 'Prints a commands data tree keys (at given depth)',
            HELP => [ 'usage:', 'use \'help\' to get a command overview, then type', '', 'keys <full cmd> [args]', '', 'to query a commands dataset.', ],
            DATA => {}
        }
    };

    return ($struct);
}
1;

