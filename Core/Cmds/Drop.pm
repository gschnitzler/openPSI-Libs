package Core::Cmds::Drop;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Search qw(tree_search_deep);

# Export
our @EXPORT_OK = qw(import_drop);

# This does what is descripted in help.
#####################################################################

sub _query ( $data, @keys ) {

    my $keyword = 'DATA';

    my $cond = sub ($branch) {
        if ( ref $branch->[0] eq 'HASH' ) {
            foreach my $item ( 'DATA', 'CMD', 'HELP' ) {
                return unless ( exists $branch->[0]->{$item} );
            }
            return 1;
        }
        return;
    };

    return tree_search_deep( $data, $cond, \@keys );
}

sub drop ( $core, @keys ) {

    my ( $hit, $misses ) = _query( $core->{cmds}, @keys );

    if ($misses) {
        say 'queried too deep or data not found, structure ended after: ', join( ' ', $misses->@* );
        return;
    }

    # now we know that @keys refer to an actual command, we can drop it
    my @path         = @keys;
    my $last_element = pop @path;
    my $current      = $core->{cmds};
    foreach my $key (@path) {
        $current = $current->{$key};
    }

    say "Dropping @keys";
    delete $current->{$last_element};
    return;
}

###############################################
# Frontend Functions

sub import_drop ($core) {

    my $struct = {
        drop => {
            CMD => sub (@args) {

                shift @args;    # contains $data
                unless (@args) {
                    say 'no keys given.';
                    return;
                }
                drop( $core, @args );
                return;
            },
            DESC => 'removes a branch from the CMD tree.',
            HELP => [
                'usage:', '', 'drop <full cmd>',
                '',
                'drops the given command.',
                'you can query a list of commands via \'help\'',
                '',
                'Used to unload user-input macros, or to unload a restored macro',
            ],
            DATA => {}
        }
    };

    return ($struct);
}
1;

