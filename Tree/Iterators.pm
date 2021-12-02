package Tree::Iterators;

use ModernStyle;
use Exporter qw(import);

our @EXPORT_OK = qw(array_iterator tree_iterator);

# this is a variant of the ever useful array iterator.
# takes any number of arrays
sub array_iterator (@arrays) {

    my $cur_elt  = 0;
    my $max_size = 0;

    foreach my $array (@arrays) {
        $max_size = $array->@* if ( $array->@* > $max_size );    # longest array
    }

    return sub () {

        if ( $cur_elt >= $max_size ) {
            $cur_elt = 0;    # this would make the iterator reuseable after it reached the end.
                             # i doubt that this would ever make sense and i would rather set a value that would make this iterator die hard,
                             # if it would be invoked again after it returned an empty list... but since its already there...
            return ();
        }

        return () if ( $cur_elt >= $max_size ); # return an empty list to indicate we are finished
        my $i = $cur_elt++;
        return ( map { $_->[$i] } @arrays );
    };
}

# a basic tree iterator
# simple as it is, this piece of code could be reused in a myriard of ways.
# the label 'tree_iterator' stems from my intention to use it for trees
#
# aside its intended use, it basically iterates through an ever expanding queue until that queue is empty,
# applying user defined code as it goes, namely:
#
# $branch_to_queue: a means of controlling the queue. you can do whatever you want there,
# but its primary purpose is to expand the queue (or not to), with contents from a branch.
#
# the queue is an array consisting of arrays of the form [ $branch, ['root', 'branch', 'branch', 'current branch' ] ]
# so $queue->[n]->[0] is a $branch ref
# and $queue->[n]->[1] is the path taken from the original $tree root to that $branch
#
# $iterator_condition is the 'counter' of the iterator.
# it controls what an iteration is.
# tree_iterator returns a $branch from the queue (controlled by $branch_to_queue) if $iterator_condition is met on that branch
#
# resist the urge to turn this into a turing machine.
sub tree_iterator ( $tree, $branch_to_queue, $iterator_condition ) {    ## no critic (Subroutines::ProhibitManyArgs)

    my @queue = [ $tree, [] ];

    return sub () {
        while (@queue) {

            my $branch = shift @queue;                                  # shift for layer after layer, pop for depth first (like recursion)
            push @queue, $branch_to_queue->($branch);

            # NEVER return with empty key list... otherwise the initial @queue key entry will remain in the queue.
            # we do not want that. (took me 3 hours to track this down.. memo to myself: don't write complicated code at 4AM)
            next if scalar $branch->[1]->@* == 0;
            return $branch if $iterator_condition->($branch);
        }
        return;
    };
}

1;
