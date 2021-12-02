package Core::Plugins::Cmds;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Core::Plugins::Data qw(plugin_data);
use Core::Plugins::Condition qw(plugin_condition);

use Tree::Search qw(tree_fraction);
use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(load_cmds);

# there might be others (like ENABLE), but these here are not optional
my $cmd_ref = {
    CMD  => 'CODE',
    HELP => 'ARRAY',
    DESC => '',        # SCALAR is not a ref
    DATA => 'HASH'

};

sub _generate_cmd ( $debug, $state, $data, $struct ) {

    my @cmds = slice_tree( $struct, plugin_condition($cmd_ref) );

    foreach my $cmd (@cmds) {

        my $cmd_def = $cmd->[0];
        my $path    = $cmd->[1];

        print_table( 'Loading Command', join( ' ', $path->@* ), ': ' ) if ($debug);

        my $enable = delete $cmd_def->{ENABLE};
        my $help   = delete $cmd_def->{HELP};

        if ( $enable && $enable eq 'no' ) {

            # completly remove it
            my ( $ref, $k ) = tree_fraction( { tree => $struct, keys => $path } );
            delete $ref->{$k};
            say 'Skipped (Disabled)' if ($debug);
            next;
        }

        $cmd_def->{DATA} = plugin_data( $state, $data, $cmd_def->{DATA} );
        $cmd_def->{HELP} = sub () { return $help; };

        say 'OK' if ($debug);
    }

    return $struct;
}

sub load_cmds ( $debug, $param ) {

    my $state      = delete $param->{state};
    my $data       = delete $param->{data};
    my $structures = delete $param->{structures};
    my $combined   = {};

    foreach my $struct ( $structures->@* ) {
        add_tree( $combined, _generate_cmd( $debug, $state, $data, $struct ) );
    }

    return $combined;
}
1;
