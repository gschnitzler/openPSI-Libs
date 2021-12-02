package Process::Message;

use ModernStyle;
use Exporter qw(import);

our @EXPORT_OK = qw(put_msg get_msg relay_msgs);

#############################################################
#
# DO NOT SAY/PRINT DEBUG MESSAGES (to STDOUT) IN THIS PACKAGE
# DO NOT DIE IN HERE
# effects would cause malfunctions in the caller
#
#############################################################

sub _encode_msg($msg) {

    if ( !defined( $msg->{to} ) || !defined( $msg->{msg} ) ) {
        say 'ERROR: invalid msg', Dumper $msg;
        return;
    }
    chomp $msg->{msg};

    return join( '', "\0", $msg->{from}, "\0", $msg->{to}, "\0", $msg->{msg} );
}

sub _decode_msg($line) {

    $line =~ s/^\0//;
    my @part = split( /\0/, $line );
    return {
        from => shift @part,
        to   => shift @part,
        msg  => join( "\0", @part )
    };
}

sub _get_unfiltered_msg ( $from, $line ) {

    chomp($line);
    my $msg = {};

    if ( $line =~ /^\0/ ) {
        $msg = _decode_msg($line);
        $msg->{from} = $from;
    }
    else {
        $msg = {
            from => $from,
            to   => 'parent',
            msg  => $line
        };
    }
    return $msg;
}

sub _buffer_line ( $buffer, $line ) {

    if ( $line =~ /\n$/s ) {
        $line = join( '', $buffer->@*, $line );
        $buffer->@* = ();    ## no critic
    }
    else {
        push $buffer->@*, $line;
        $line = '';
    }
    return $line;
}

###############################################

#used by clients only. pad the from part. clients dont supply it
sub put_msg($msg) {

    $msg->{from} = '_';
    say _encode_msg($msg);
    return;
}

# this is used by clients, messages are always formatted
sub get_msg (@lines) {

    my @messages = ();
    foreach my $line (@lines) {

        chomp($line);
        push @messages, _decode_msg($line);
    }

    return wantarray ? @messages : $messages[0];    # when the caller only supplies on argument, it expects SCALAR context
}

sub relay_msgs ( $self, $others, @lines ) {

    my @parent = ();
    my $from   = $self->{PID}->{name};

    while ( my $line = shift @lines ) {

        # lines are supposed to end with a newline.
        # buffer lines that were to eagerly read, complete them once they are finished
        $line = _buffer_line( $self->{BUFFER}, $line );
        next unless ($line);

        my $msg = _get_unfiltered_msg( $from, $line );

        if ( $msg->{to} eq 'parent' ) {
            push @parent, $msg;
            next;
        }

        my $sent = 0;
        foreach my $worker ( $others->@* ) {

            last if ($sent);
            if ( exists( $worker->{PID}->{name} ) && $worker->{PID}->{name} eq $msg->{to} ) {
                $worker->{PID}->write_stdin( _encode_msg($msg), "\n" );
                $sent++;
            }
        }
        say 'ERROR: invalid recipient \'', $msg->{to}, '\' from \'', $msg->{from}, '\'', ' msg: \'', $msg->{msg}, '\'' unless $sent;
    }
    return @parent;
}
