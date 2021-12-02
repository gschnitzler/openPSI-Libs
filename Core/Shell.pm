package Core::Shell;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Search qw(tree_search_position);

use Core::Shell::Variables qw(replace_variables);
use Core::Shell::Input qw(filter_input);

our @EXPORT_OK = qw(core_shell);

my $buildin = {

    # internal command used to test Tree operations
    # used by macros to test if all the commands in a macro are valid
    test => sub ( $core, @args ) {
        my ( $cmd, $path, $args ) = _query_cmds( $core, \@args );

        return 0 if ($cmd);
        say "Unknown Command or missing: @args";
        return 1;
    }
};

sub _query_cmds ( $core, $keys ) {

    my $cond = sub ($branch) {
        return 1 if ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{CMD} ) && ref $branch->[0]->{CMD} eq 'CODE';
        return;
    };

    my ( $cmd, $path, $args ) = tree_search_position( $core->{cmds}, $cond, $keys );

    return ( $cmd, $path, $args );
}

sub _core_shell ( $core, $args ) {

    my $variables      = $core->{variables};
    my @args_sanitized = filter_input($args);

    return 0 if ( scalar @args_sanitized == 0 );
    return 1 if ( replace_variables( $variables, \@args_sanitized ) );

    # buildin aliases
    if ( exists $buildin->{ $args_sanitized[0] } ) {

        my $buildin_return = $buildin->{ $args_sanitized[0] }->( $core, @args_sanitized[ 1 .. $#args_sanitized ] );
        return $buildin_return;
    }

    my ( $cmd, $path, $cmd_args ) = _query_cmds( $core, \@args_sanitized );

    if ($cmd) {

        my $start_time = time();
        my $return     = $cmd->{CMD}->( $cmd->{DATA}, $cmd_args->@* );
        $return = 0 unless $return;

        printf( 'Runtime: %02d:%02d:%02d ', ( gmtime( time() - $start_time ) )[ 2, 1, 0 ] );
        say "($path->@*, $cmd_args->@*), Return Code: $return";

        # we do not want to die if a command failed.
        # devs should decide if their commands die on internal errors or just return an error code to be handled by whatever invokes the shell.
        return $return;
    }
    say 'Unknown Command, type \'help\'';

    # let macros know it broke.
    # macros are checked for complete commands (via test buildin) before execution.
    # at some point someone will use drop within a macro and wonder whats wrong :)
    return 1;
}

sub _trap($when, $cmd, $ec, $msg){
    say "\n\n>>>>>>>>>> CORE: It's a trap! EC:$ec MSG:'$msg' $when '$cmd'\n" if ( $ec or $msg );
}

sub core_shell($tree) {

    return sub($args) {
        local ($?, $!);
        $tree->{ID}->($tree);    # check for modifications
        _trap('before', $args, $?, $!);
        my $return = _core_shell( $tree, $args );
        _trap('after', $args, $?, $!);
        $tree->{ID}->($tree);    # check for modifications
        return $return;
    };
}
1;
