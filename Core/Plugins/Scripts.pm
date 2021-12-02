package Core::Plugins::Scripts;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Core::Plugins::Condition qw(plugin_condition);
use Core::Plugins::Data qw(plugin_data);

use IO::Templates::Parse qw(check_and_fill_template get_variable_tree);
use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);
use Tree::Build qw(build_tree_data);

use PSI::RunCmds qw(run_cmd);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(load_scripts);

my $script_ref = {
    CONTENT => 'ARRAY',
    CHMOD   => ''         # is a SCALAR, but not a SCALAR reference.
};

sub _read_script ($script) {

    my @action    = ();
    my @multiline = ();

    foreach my $line ( $script->@* ) {

        unless (@multiline) {
            next if ( $line =~ /^\#/x );    # skip comments unless inside multiline # x requires \#
            next if ( $line eq '' );        # skip empty lines unless in multiline
        }

        if ( $line =~ /(cat|patch).*EOF/x ) {

            push @multiline, join( '', $line, "\n" );
            next;
        }

        if ( $line eq 'EOF' ) {

            push @multiline, join( '', $line, "\n" );
            push @action, join( '', @multiline );
            @multiline = ();
            next;
        }

        push @multiline, join( '', $line, "\n" ) if (@multiline);
        push @action, $line unless (@multiline);    # normal newlines are inserted at execution
    }
    return (@action);
}

sub _script_cmd ($cmds) {

    return sub ( $query, @args ) {

        my $data    = $query->();
        my $script  = check_and_fill_template( $cmds, $data );
        my @actions = _read_script($script);

        run_cmd(@actions);
        return;
    };
}

sub _generate_scripts ( $debug, $p ) {

    my $state        = $p->{state};
    my $data         = $p->{data};
    my $scripts_list = $p->{scripts};
    my @scripts      = slice_tree( $scripts_list, plugin_condition($script_ref) );

    foreach my $script (@scripts) {

        my $script_def = $script->[0];
        my $path       = $script->[1];

        print_table( 'Loading Script', join( ' ', $path->@* ), ': ' ) if ($debug);

        delete $script_def->{CHMOD}; # unneeded

        my $content = delete $script_def->{CONTENT};

        $script_def->{DESC} = 'no description available';
        $script_def->{HELP} = sub () {
            return ['generic script, no help available.'];
        };
        $script_def->{DATA} = plugin_data( $state, $data, build_tree_data( {}, sub (@args) { return $args[1] }, get_variable_tree($content) ) );
        $script_def->{CMD}  = _script_cmd($content);

        say 'OK' if ($debug);
    }

    return $scripts_list;
}

sub load_scripts ( $debug, $state, $data, $scripts ) {

    my $combined = {};

    add_tree(
        $combined,
        _generate_scripts(
            $debug,
            {
                state   => $state,
                data    => $data,
                scripts => $scripts,
            }
        )
    ) if ( $scripts && scalar keys $scripts->%* != 0 );

    return $combined;
}
1;
