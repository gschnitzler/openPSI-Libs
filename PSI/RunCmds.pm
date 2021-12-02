package PSI::RunCmds;

use ModernStyle;
use Exporter qw(import);
use Carp;

our @EXPORT_OK = qw(run_cmd run_system run_open);

sub _rescueshell ( $p ) {

    # reset
    local ( $!, $? );
    $! = undef if $!;
    $? = undef if $?;
    say "ERROR: EC:$p->{ec}, CC:$p->{child_ec}, SIG:$p->{signal}, CD:$p->{coredump}, MSG:'$p->{msg}' on '$p->{cmd}'\n";
    say ">>>>>>>>>>>>>>>>>>>>> RESCUE SHELL: 'exit 0' when successfull, otherwise 'exit 1'\n";

    # the rescueshell file is used for Build::Cmds::Build
    # while genesis is required to be run as root, other programs might.
    # yet, this Module is used by Core::Cmds::System.
    # non-root users cant write to /, but /tmp might not yet exist when buildmanager throws an error
    # This filepath should not be hardcoded
    system('touch /rescueshell') or print '';
    system('/bin/bash')          or print '';
    if ($?) {
        say "ERROR: $? on $p->{cmd}";
        return $?;
    }
    unlink '/rescueshell' or print '';
    return;
}

sub _close_handler ( $cmd, $msg, $ec ) {
    $ec = $ec >> 8;
    confess "ERROR: closing '$cmd': MSG:'$msg' EC:'$ec'";
}

sub _open_handler ( $cmd, $msg, $ec ) {
    $ec = $ec >> 8;
    confess "ERROR: opening '$cmd': MSG:'$msg' EC:'$ec'";
}

sub _read_handler ( $stop, $line ) {
    chomp $line;
    return $line;
}
#######################################################################

sub run_cmd (@cmds) {
    return run_system( \&_rescueshell, @cmds );
}

sub run_system ( @cmds ) {

    chdir '/' or die 'ERROR: could not chdir /';    # as scripts could alter our working directory, chdir / before
    confess "ERROR: It's a trap! EC:$? MSG:'$!'" if ( $! or $? );
    my $handler = ( ref $cmds[0] eq 'CODE' ) ? shift @cmds : undef;    # optional handler

    foreach my $cmd (@cmds) {

        local ( $!, $? );                                              # don't let anything escape
        system join( "\n", $cmd ) or print '';                         # the newline is added in case a $cmd has multiple lines but no trailing newline,
                                                                       # rendering the shell unable to parse the last statement. like EOF.
        next unless $?;

        my $p = {
            cmd      => $cmd,
            ec       => $?,
            msg      => $!,
            signal   => $? & 127,
            coredump => ( $? & 128 ) ? '1' : '0',
            child_ec => $? >> 8,
        };

        if ($handler) {
            next unless $handler->($p);
        }

        confess "ERROR: '$cmd' failed: $p->{msg}" if ( $p->{ec} == -1 );
        confess "ERROR: '$cmd' received SIG:$p->{signal}, coredump:$p->{coredump}" if $p->{signal};
        confess "ERROR: '$cmd' returned EC:$p->{child_ec} MSG:'$p->{msg}'";
    }
    return 0;
}

sub run_open ( $cmd, @args ) {

    local ( $!, $? );
    my $close_handler = ( ref $args[0] eq 'CODE' ) ? $args[0] : \&_close_handler;    # optional handler for closing
    my $open_handler  = ( ref $args[1] eq 'CODE' ) ? $args[1] : \&_open_handler;     # optional handler for opening
    my $read_handler  = ( ref $args[2] eq 'CODE' ) ? $args[2] : \&_read_handler;     # optional handler for reading
    my @output        = ();
    my $stop_reading  = 0;
    confess "ERROR: It's a trap! EC:$? MSG:'$!'" if ( $! or $? );

    return unless ( open( my $fh, '-|', $cmd ) or $open_handler->( $cmd, $!, $? >> 8) );    # don't return true in the open_handler on error,
                                                                                        # otherwise execution will continue
    while ( my $line = <$fh> ) {
        push @output, $read_handler->( \$stop_reading, $line );                         # handler should return whatever is desired in @output.
                                                                                        # in cases where you want to stop reading streams, like tail -f,
                                                                                        # a callback can be set via ${$stop}++ in the handler
        if ($stop_reading) {
            close $fh or print '';    # when you stop reading from a stream, you don't care about the exit code
            return @output;           # and close will return false in any case, so lets skip that
        }
    }

    close $fh or $close_handler->( $cmd, $!, $? >> 8);    # no 'return unless' used as it makes no sense to not return @output
    return @output;
}

1;
