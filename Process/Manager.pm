package Process::Manager;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

# Forks::Super 0.93 or greater required.
# see https://rt.cpan.org/Public/Bug/Display.html?id=124316
use Forks::Super;
use Time::HiRes qw(sleep);

use Process::Message qw(relay_msgs);
use PSI::Console qw(print_table);

Readonly my $SLEEP_INTERVAL => 0.2;
Readonly my $KILL_SIGNAL    => 9;

our @EXPORT_OK = qw(task_manager);

# uninstall Forks::Super after loading.
# pulling in forks super calls the die chld bug:
# package needs to deinit forks::super and only enable it in the task_manager
Forks::Super->deinit_pkg;

##########################################################

sub _convert_tree ($worker_tree) {

    my @q = ();
    foreach my $name ( keys( $worker_tree->%* ) ) {
        my $w = $worker_tree->{$name};
        push @q, [ $name, $w ];
    }
    return @q;
}

sub _init_workers ( $debug, $max_slots, $used_slots, $workers ) {

    my @initialized = ();

    while ( my $e = shift $workers->@* ) {

        if ( $max_slots - ${$used_slots} <= 0 ) {
            push $workers->@*, $e;
            last;
        }

        my $name   = $e->[0];
        my $w      = $e->[1];
        my $worker = {
            QUEUE  => $w->{QUEUE},
            BUFFER => {},
            FLUSH  => {},
            PID    => fork {
                max_proc => 0,                     # 0 gives uninitialized value, use -1, fixed in 0.93
                name     => $name,
                sub      => $w->{TASK},
                args     => $w->{DATA},
                child_fh => 'in,out,err,:utf8',    # sockets impose a buffer limit. which is bad. pipes are even worse. so stick to temp files.
                                                   # took me 2 days to track this down. jobs would hang with unread buffers when you write to much to stdout
            },
        };

        # time limit on child processes
        # $pid = fork { cmd => $cmd, timeout => 30 };  # kill child if not done in 30s
        # i dont like the fiddling with SIG{ALARM} after what i've seen with SIG{CHLD]. the poor mans version also sucks.
        # as we already have a loop for the messaging, we will use that.
        $worker->{TIMEOUT} = time + $w->{TIMEOUT} if ( exists( $w->{TIMEOUT} ) );

        die 'ERROR: could not fork.'                             if ( !$worker->{PID} );
        print_table( $name, "(PID: $worker->{PID}))", ": OK\n" ) if ($debug);
        push @initialized, $worker;
        ${$used_slots}++;
    }
    return @initialized;
}

sub _print_parent_msg ( $msg, $debug ) {
    say 'from: ', $msg->{from}, ' msg: ', $msg->{msg} if $debug;
    say $msg->{msg};
    return;
}

sub _relay_msgs ( $debug, $self, $others, $msg_handler ) {

    my @lines = (
        [ 'err', [ $self->{PID}->read_stderr() ] ],    #
        [ 'out', [ $self->{PID}->read_stdout() ] ]     #
    );

    # read_stderr and read_sdtout feature standard diagnostics of nothing could be read.
    # thats ok. to make debugging easier:
    $? = $! = 0;    ## no critic

    foreach my $msg ( relay_msgs( $self, $others, @lines ) ) {
        ref $msg_handler eq 'CODE' ? $msg_handler->( $msg, $debug ) : _print_parent_msg( $msg, $debug );    # these are for the parent
    }
    return;
}

sub _cleanup_worker ($worker) {    # empty buffer

    if ( scalar keys $worker->{BUFFER}->%* || scalar keys $worker->{FLUSH}->%* ) {
        say "WARNING: process $worker->{PID}->{name} had an unread buffer on exit:";
        say "BUFFER:", Dumper $worker->{BUFFER};
        say "FLUSH: ", Dumper $worker->{FLUSH};
    }
    say "WARNING: process $worker->{PID}->{name} exit code was: $worker->{PID}->{status}" if ( $worker->{PID}->{status} );

    $worker->{PID}->wait();
    $worker->{PID}->dispose();

    # dispose emits 'No such file or directory'.thats ok.
    $? = $! = 0;    ## no critic

    delete $worker->{PID};
    return;
}

sub task_manager ( $debug, $workers, $max_slots, @args ) {

    my $msg_handler = shift @args;

    # this single line took me way over 20h to figure out.
    # so Forks::Super sets $SIG{CHLD}=sub{} if(!defined($SIG{CHLD}))
    # somewhere in Super.pm to circumvent a behaviour issue.
    # it then proceeds to setup its own handler later on.
    # thing is, it does not unregister it on exit, leading to strange action at the distance,
    # like every other 'close or die' to fail randomly. (if it spawns another process with |)
    # having a local version set to undef (the default on my system) will reset $SIG{CHLD} upon returning.
    # maybe this gets fixed sometime in the future. https://rt.cpan.org/Public/Bug/Display.html?id=124316
    # up until then, this is the workaround.
    # be warned though, that this does not prevent issues within this module.
    # so if you use things like open | in this module, undef the handler before your codeblock, run the code, then set it back to the handler.
    #local $SIG{CHLD} = undef;
    # as of 0.93, this is fixed via calls to init_pkg und deinit_pkg
    Forks::Super->init_pkg;

    # seems like Forks::Super evals the subroutines, so die and friends wont write to STDERR, and we are not given access to $@.
    # as a workaround, we force die and friends. why does it always get ugly with perl?
    #local $SIG{__DIE__} = sub { print STDERR @_ };
    # also fixed in 0.93

    # be sure to set all SIG handlers that clash with Forks::Super before the first invocation of anything Forks::Super related
    # TERM and INT are fine though.

    my $die = sub {
        say time(), ': received sigint/term, shutting down ungracefully.';
        my @killed = Forks::Super::kill_all 'TERM';
        say join( ' ', 'killed childs:', @killed );
        exit 1;
    };

    local $SIG{TERM} = $die;
    local $SIG{INT}  = $die;

    # we receive a dependency tree of tasks
    # every root node is added to a queue
    my $used_slots = 0;
    my @waiting    = _convert_tree($workers);
    my @running    = _init_workers( $debug, $max_slots, \$used_slots, \@waiting );

    # not the most elegant, but easy to implement.
    while (1) {

        last          if ( $#running < 0 );
        say '=CYCLE=' if $debug;
        sleep $SLEEP_INTERVAL;
        my $time = time;

        # process the queue. we want to iterate over all entries, adding and deleting whenever a worker finished.
        # the easiest and one of the fastest methods is also the least elegant: creating a new array
        my @cur_running = ();

        foreach my $worker (@running) {

            _relay_msgs( $debug, $worker, [ @running, @cur_running ], $msg_handler );

            if ( $worker->{PID}->is_complete ) {

                _cleanup_worker($worker);

                # add new ones to queue
                push @waiting, _convert_tree( $worker->{QUEUE} ) if ( ref $worker->{QUEUE} eq 'HASH' );
                $used_slots--;
            }
            elsif ( exists( $worker->{TIMEOUT} ) && $worker->{TIMEOUT} < $time ) {

                # process overstayed its welcome. kill it and print out a warning.
                # this results in bad state, but its better than to die here, which might result in even worse state.
                # dont push its queue on the stack.
                $worker->{PID}->kill($KILL_SIGNAL);
                say 'WARNING: killed task ', $worker->{PID}->{name}, ' with PID ', $worker->{PID}, ' (timeout)';
                _cleanup_worker($worker);
                $used_slots--;
            }
            else {
                push @cur_running, $worker;
            }
        }

        # start new jobs if slots got available
        push @cur_running, _init_workers( $debug, $max_slots, \$used_slots, \@waiting );
        @running = (@cur_running);
    }
    waitall();

    # waitall emits an error code. Forks::Super installs its own $SIG{CHLD} handler.
    # so the value is actual garbage, but others might read it
    # get rid of it
    $? = $! = 0;    ## no critic

    # https://rt.cpan.org/Public/Bug/Display.html?id=124316
    # to work around side-effects at the distance, call this
    Forks::Super->deinit_pkg;

    return;
}

1;
