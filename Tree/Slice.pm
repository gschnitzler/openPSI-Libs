package Tree::Slice;

use ModernStyle;
use Exporter qw(import);
use Carp;

use Tree::Iterators qw(tree_iterator);

our @EXPORT_OK = qw(slice_tree);

# this is the default $branch_to_queue implementation
# basically if we find another node (hash), we want to push it on the queue
# if we want some more sophisticated analysis, we would need to supply a callback function here or curry something
# in order to track the path, we store the keys in an array
sub _tree_branch_to_queue ($branch) {

    return unless ref $branch->[0] eq 'HASH';
    my @nodes = ();

    foreach my $k ( keys $branch->[0]->%* ) {    # never use while
        my $v = $branch->[0]->{$k};

        #           say "key___: $k, value: $v";
        # maybe we could also add arrays here
        # then we would have to enclose the while in if( ref $branch eq HASH)
        push @nodes, [ $v, [ $branch->[1]->@*, $k ] ];    # if ref $v eq 'HASH';
    }
    return @nodes;
}

sub slice_tree ( $tree, $iterator_condition, @args ) {

    my $branch_to_queue = shift @args;
    my $depth           = shift @args;

    confess 'ERROR: no condition given' if ( ref $iterator_condition ne 'CODE' );
    $branch_to_queue = \&_tree_branch_to_queue unless $branch_to_queue; # default to _tree_branch_to_queue unless an alternative is given
    confess 'ERROR: supplied $branch_to_queue is not a code ref' unless ( ref $branch_to_queue eq 'CODE' );

    my $it   = tree_iterator( $tree, $branch_to_queue, $iterator_condition ); # set up iterator
    my @hits = ();

    # only use elements that match our search length
    while ( defined( my $hit = $it->() ) ) {

        last if $depth && $depth < scalar $hit->[1]->@*; # break once we reach the maximum depth of interest, if given

        #say "walk__: $hit->[0], $hit->[1]->@*, $keys->@*";
        push @hits, $hit;
    }
    return @hits;
}

1;
