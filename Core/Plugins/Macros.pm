package Core::Plugins::Macros;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw (nstore);

use Core::Plugins::Condition qw(plugin_condition);
use Core::Shell::Variables qw(replace_variables);
use Core::Shell::Input qw(filter_input);

use Core::Query qw(query);

use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);
use PSI::Console qw(print_table);

our @EXPORT_OK = qw(load_macros);

my $macro_ref = {
    MACRO => 'ARRAY',
    HELP  => 'ARRAY',
    DESC  => ''         # is a SCALAR, but not a SCALAR reference. took me 2h to figure out the resulting problem.
                        # never write clever code at 2am
};

sub _check_macro_buildins($queue) {

    my $buildin = {
        SAVE       => 0,
        SAVECHROOT => 0,    # this will prefix $macromount to $macrosave
        CONTINUE   => 0
    };

    # there could be multiple SAVE and CONTINUE statements inside a queue (for whatever reason)
    # but there should be the same amount of both
    while ( my $item = shift $queue->@* ) {
        if ( $item eq 'CONTINUE' ) {
            $buildin->{CONTINUE}++;
        }
        else {
            next                     if $item =~ /^\s*$/x;           # drop empty lines
            $buildin->{SAVECHROOT}++ if ( $item eq 'SAVECHROOT' );
            $buildin->{SAVE}++       if ( $item eq 'SAVE' );
        }
    }
    die 'ERROR: no equal amount of SAVE and CONTINUE statements.'
        unless ( ( $buildin->{SAVE} + $buildin->{SAVECHROOT} ) == $buildin->{CONTINUE} );

    return $buildin;
}

sub _split_macro_queue($queue) {

    my @before_continue = ();
    while ( my $item = shift $queue->@* ) {

        last if ( $item eq 'CONTINUE' );
        push @before_continue, $item;
    }

    return $queue, \@before_continue;
}

sub _test_shell_cmds ( $shell, $buildin, @args ) {

    foreach my $queue (@args) {

        # check for completeness
        foreach my $line ( $queue->@* ) {

            next if exists $buildin->{$line}; # shell does not know about buildins
            say "$line";

            # the test command below also checks for variables
            die "macro command '$line' is not available. cannot execute macro" if ( $shell->( join( ' ', 'test', $line ) ) );
        }
    }
    return;
}

sub _replace_variables ( $buildin, $variables, @queue ) {

    my @substituted_queue = ();

    foreach my $line (@queue) {

        next if exists $buildin->{$line};# shell does not know about buildins

        my @filtered_line = filter_input($line);
        my $failed_variable = replace_variables( $variables, \@filtered_line );

        if ( $failed_variable eq '1' ) {    # otherwise its a string
            die 'ERROR: cannot execute macro, required variables not set';
        }
        push @substituted_queue, join( ' ', @filtered_line );
    }

    return \@substituted_queue;
}

sub _save_macro_queue ( $queue_tosave, $macrosave_path ) {

    print 'saving queue...';
    local ($?, $!);
    nstore $queue_tosave, $macrosave_path or die 'ERROR: could not open macro save file';
    say ' done.';
    return;
}

sub _curry_shell ( $core ) {

    my $shell      = $core->{shell};
    my $variables  = $core->{variables};
    my $macrosave  = $core->{CONFIG}->('MACROSAVE');
    my $macromount = $core->{CONFIG}->('MACROMOUNT');

    # NOTES:
    # WE CANT RETURN ON ERROR IN THIS FUNCTION
    # because macros could be nested

    # additionally, if a nested macro performs a save, the parent queue is lost.
    # but i believe that it would not make sense to write a macro like that.
    #
    # i also cant think of a situation where multiple SAVE/CONTINUE blocks within a macro would make sense (enter a chroot within a chroot?)
    # but it COULD make sense, so it is implemented.
    # allthough right now, there is only ONE 'savefile' supported. so one would really need to chroot multiple times to make use of this.
    # might implement SAVE <name> and restore functionality once needed (which would grand a lot of headache)
    # but as it is, this whole construct is just for the sake of chroot. so... probably not :)
    return sub ($query) {

        my $buildin = _check_macro_buildins( $query->() );

        # split queue into before and after first CONTINUE
        my ( $queue, $toexecute ) = _split_macro_queue( $query->() );

        _test_shell_cmds( $shell, $buildin, $toexecute, $queue );

        foreach my $line ( $toexecute->@* ) {

            if ( $line eq 'SAVE' ) {

                # now check the remaining queue for variables and replace them
                # as the macro could have set variables itself, now is the earliest time
                _save_macro_queue( _replace_variables( $buildin, $variables, $queue->@* ), $macrosave );
            }
            elsif ( $line eq 'SAVECHROOT' ) {

                # now check the remaining queue for variables and replace them
                # as the macro could have set variables itself, now is the earliest time
                _save_macro_queue( _replace_variables( $buildin, $variables, $queue->@* ), join( '', $macromount, $macrosave ) );
            }
            else {

                my $return = $shell->($line);

                # whoever invokes the shell has the power to deal with errors.
                # here, there is nothing to handle errors... so let the user know
                die "ERROR: execution of '$line' returned '$return'" if $return;
            }
        }
    };
}

sub _generate_macros ( $debug, $shell, $macro_list ) {

    #   say Dumper $macro_list;
    my @macros = slice_tree( $macro_list, plugin_condition($macro_ref) );

    foreach my $macro (@macros) {

        #    say Dumper $macro;
        my $macro_def = $macro->[0];
        my $path      = $macro->[1];

        print_table( 'Loading Macro', join( ' ', $path->@* ), ': ' ) if ($debug);

        my $help  = delete $macro_def->{HELP};
        my $macro = delete $macro_def->{MACRO};

        $macro_def->{HELP} = sub () { return $help; };
        $macro_def->{DATA} = query($macro);
        $macro_def->{CMD}  = $shell;

        say 'OK' if ($debug);

    }
    return $macro_list;
}

sub load_macros ( $core, $macros ) {

    my $combined = {};
    my $debug    = $core->{CONFIG}->('DEBUG');
    my $shell    = _curry_shell($core);

    add_tree( $combined, _generate_macros( $debug, $shell, $macros ) ) if ( $macros && scalar keys $macros->%* != 0 );
    return $combined;
}
1;
