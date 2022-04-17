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

sub _encode_msg ($msg) {

    if ( !defined( $msg->{to} ) || !defined( $msg->{msg} ) ) {
        say 'ERROR: invalid msg', Dumper $msg;
        return;
    }
    chomp $msg->{msg};

    return join( '', "\0", $msg->{from}, "\0", $msg->{to}, "\0", $msg->{msg} );
}

sub _decode_msg ($line) {

    $line =~ s/^\0//;
    my @part = split( /\0/, $line );
    return {
        from => shift @part,
        to   => shift @part,
        msg  => join( "\0", @part )
    };
}

sub _get_unfiltered_msg ( $from, $line ) {

    chomp $line;
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

sub _is_partial($s) {
    $s =~ /\n$/ ? return 0 : return 1;
}

sub _add_to_buffer ( $buffer, $flush, $from, $stream ) {
    my $stream_name = $stream->[0];

    while ( my $line = shift $stream->[1]->@* ) {

        my $is_partial = _is_partial($line);
        my $msg        = _get_unfiltered_msg $from, $line;
        my $to         = $msg->{to};
        $buffer->{$stream_name}->{$to} = () unless ref $buffer->{$stream_name}->{$to} eq 'ARRAY';
        push $buffer->{$stream_name}->{$to}->@*, $msg->{msg};
        next if $is_partial;
        $flush->{$stream_name}->{$to} = () unless ref $flush->{$stream_name}->{$to} eq 'ARRAY';
        push $flush->{$stream_name}->{$to}->@*, join '', delete( $buffer->{$stream_name}->{$to} )->@*;
        delete $buffer->{$stream_name} unless scalar keys $buffer->{$stream_name}->%*;
    }
    return;
}

###############################################

#used by clients only. pad the from part. clients dont supply it
sub put_msg ($msg) {

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

sub relay_msgs ( $self, $others, @streams ) {

    my @parent = ();
    my $from   = $self->{PID}->{name};
    my $flush  = $self->{FLUSH};

    for my $stream (@streams) {
        _add_to_buffer $self->{BUFFER}, $flush, $from, $stream;
    }

    for my $stream_name ( keys $flush->%* ) {
        my $flush_stream = delete $flush->{$stream_name};

        for my $to ( keys $flush_stream->%* ) {
            my $flush_stream_to = $flush_stream->{$to};
            
            for my $msg ( $flush_stream_to->@* ) {
                my $msg = {
                    from => $from,
                    to   => $to,
                    msg  => $msg
                };

                if ( $to eq 'parent' ) {
                    push @parent, $msg;
                    next;
                }

                my $sent = 0;
                for my $worker ( $others->@* ) {
                    last if ($sent);
                    if ( exists( $worker->{PID}->{name} ) && $worker->{PID}->{name} eq $msg->{to} ) {
                        $worker->{PID}->write_stdin( _encode_msg($msg), "\n" );
                        $sent++;
                    }
                }
                say 'ERROR: invalid recipient \'', $msg->{to}, '\' from \'', $msg->{from}, '\'', ' msg: \'', $msg->{msg}, '\'' unless $sent;
            }
        }
    }
    return @parent;
}
