#!/usr/bin/perl
use lib '/data/psi/Libs';

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Time::HiRes qw(sleep);
use Carp;

use PSI::RunCmds qw(run_cmd);
use Process::Message qw(get_msg put_msg);
use Process::Manager qw(task_manager);

#########################################################

my $debug   = 0;
my $workers = {
    A => {
        TASK => sub ($data) {
            local $! = 0;
            local $? = 0;

            my $task_name = 'A';
            my ( $k, $v ) = ( $data->%* );
            say "$task_name started";
            sleep 1;
            print "bla1\nbla2\nbla3\nbla4\nbla5\nbla6";
            sleep 1;
            print "_7";
            sleep 1;
            say "_8";
            sleep 1;
            run_cmd('echo bla');
            put_msg(
                {
                    to  => 'B',
                    msg => "$task_name says hi to B, btw my data key is $k and the value $v"
                }
            );
            put_msg(
                {
                    to  => 'parent',
                    msg => "$task_name puts_msg to parent"
                }
            );
            sleep 1;
            say "$task_name say msg to parent";
            say "$task_name finished";
            return;
        },
        DATA  => { HI => '2' },
        QUEUE => {
            AB => {
                TASK => sub ($data) {
                    my $task_name = 'AB';
                    my ( $k, $v ) = ( $data->%* );

                    say "$task_name started";
                    sleep 1;
                    put_msg(
                        {
                            to  => 'B',
                            msg => "$task_name says hi to B, btw my data key is $k and the value $v"
                        }
                    );
                    put_msg(
                        {
                            to  => 'parent',
                            msg => "$task_name puts_msg to parent"
                        }
                    );
                    sleep 1;
                    say "$task_name say msg to parent";
                    say "$task_name finished";

                    #say STDERR "woooo";
                    die "ERRRRRROOOOORRRRRRRRRRRRRR successfully tested";
                },
                DATA => { TO => '3' },
            },
            AC => {
                TASK => sub ($data) {

                    my $task_name = 'AC';
                    my ( $k, $v ) = ( $data->%* );

                    say "$task_name started";
                    sleep 1;
                    put_msg(

                        {
                            to  => 'B',
                            msg => "$task_name says hi to B, btw my data key is $k and the value $v"
                        }
                    );
                    put_msg(
                        {
                            to  => 'parent',
                            msg => "$task_name puts_msg to parent"
                        }
                    );
                    sleep 1;
                    say "$task_name say msg to parent";

                    print 'this ';
                    sleep 0.5;
                    print 'is';
                    sleep 0.5;
                    print ' a';
                    sleep 0.5;
                    print ' slow ';
                    sleep 0.5;
                    say 'message';
                    sleep 0.5;

                    say "$task_name will finish after 5";

                    my $i = 1;
                    while (1) {

                        sleep 0.5;
                        put_msg(
                            {
                                to  => 'B',
                                msg => "i tell you $i"
                            }
                        );
                        last if $i == 5;
                        $i++;
                    }
                    say "$task_name THATS IT I QUIT";
                    put_msg(
                        {
                            to  => 'B',
                            msg => "THATS IT I QUIT"
                        }
                    );

                    return;
                },
                DATA => { BE => '4' },
            },
        },
    },

    B => {
        TASK => sub ($data) {
            my $task_name = 'B';
            my ( $k, $v ) = ( $data->%* );

            say "$task_name started";

            put_msg(
                {
                    to  => 'parent',
                    msg => "$task_name puts_msg to parent"
                }
            );
            say "$task_name say msg to parent";
            say "$task_name will only finish after AC!";

          GETOUT: while (1) {

                local ( $!, $? );

                #while ( !eof(STDIN) ) {
                #    defined( $_ = readline STDIN ) or die "readline failed: $!";
                #    my $msg = get_msg($_);
                foreach my $msg ( get_msg( readline(STDIN) ) ) {
                    
                    put_msg(
                        {
                            to  => 'parent',
                            msg => "B received: $msg->{msg}"
                        }
                    );
                    last GETOUT if ( $msg->{msg} eq "THATS IT I QUIT" );
                }
                sleep 0.2;
            }
            return;

            while (1) {

                my @msgs = get_msg(<STDIN>);
                foreach my $msg (@msgs) {
                    put_msg(
                        {
                            to  => 'parent',
                            msg => "B received: $msg->{msg}"
                        }
                    );
                    return if ( $msg->{msg} eq "THATS IT I QUIT" );
                }

                sleep 0.2;

            }
            say "$task_name HERE BE DRAGONS";

            return;
        },
        DATA => {},
    },
    T => {
        TASK => sub ($data) {
            my $task_name = 'T';
            my ( $k, $v ) = ( $data->%* );

            say "$task_name started";
            sleep 100;
            say "$task_name HERE BE DRAGONS";

            return;
        },
        DATA    => {},
        TIMEOUT => 5,
    }

};

task_manager( $debug, $workers, 20 );

