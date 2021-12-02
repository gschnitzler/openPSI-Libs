package Core::Cmds::Macro;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw (retrieve);

use Core::Plugins::Macros qw(load_macros);
use Core::Query qw(query);

our @EXPORT_OK = qw(import_macro);

# This interfaces the macro system.
# enables users to define and execute macros as one-offs.
# also interfaces the loading of disk-stored macros
####################################################

sub _create_macro ( $core, $cmds ) {

    my $macro = {
        _macro => {
            HELP  => ['internal'],
            DESC  => 'internal',
            MACRO => $cmds

        }
    };

    my $compiled = load_macros( $core, $macro );
    return $compiled->{_macro};
}

sub _run ( $core, @ ) {

    my @input = ();

    say 'enter commands. Type \'EOF\' on its own line when finished';

    # if genesis is called via commandline arguments, <> does not work, so STDIN is used
    # ignore perl critic
    while ( my $line = <STDIN> ) {    ## no critic (InputOutput::ProhibitExplicitStdin)

        chomp $line;

        $line =~ s/^\s*//x;
        $line =~ s/\s*$//x;
        last if ( $line eq 'EOF' );
        push @input, $line;
    }

    my $compiled_macro = _create_macro( $core, \@input );
    say 'running macro...';
    return $compiled_macro->{CMD}->( $compiled_macro->{DATA} );
}

sub _load ( $core, @ ) {

    my $macrosave = $core->{CONFIG}->('MACROSAVE');
    my $macro;
    say 'reading macro queue (from disk)...';
    {
        local ( $?, $! );
        $macro = retrieve($macrosave) or die 'ERROR opening file';
    }

    say 'deleting macro queue (on disk)...';
    unlink $macrosave or die 'ERROR: could not delete macro save file';
    my $compiled_macro = _create_macro( $core, $macro );
    say 'resuming macro queue...';
    return $compiled_macro->{CMD}->( $compiled_macro->{DATA} );
}

###############################################
# Frontend Functions

sub import_macro ($core) {

    my $struct = {
        macro => {
            run => {
                CMD => sub ( $query, @args ) {
                    _run( $core, @args );
                },
                DESC => 'create a macro and run it',
                HELP => [
                    'usage: macro run',
                    '<input multiline set of commands, ended with \'EOF\' on its own line>',
                    '',
                    'once EOF is issued, the macro is executed.',
                    'the macro is discarded after completion.'
                ],
                DATA => {}
            },
            load => {
                CMD => sub ( $query, @args ) {
                    _load( $core, @args );
                },
                DESC => 'loads saved macro queue from disk',
                HELP => [ 'usage: macro load', 'loads queue from disk. only useful in junction with chroot.', ],
                DATA => {}
            }
        }
    };

    return ($struct);
}
1;

