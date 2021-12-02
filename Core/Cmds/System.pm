package Core::Cmds::System;

use ModernStyle;
use Exporter qw(import);

use PSI::RunCmds qw(run_cmd);

# Export
our @EXPORT_OK = qw(import_system);

# this might come in handy in macros,
# or when you do not want to leave a shell , because you have macros or variables defined

###############################################
# Frontend Functions

sub import_system () {

    my $struct = {
        system => {
            CMD => sub (@args) {
                shift @args;    # contains $data
                unless (@args) {
                    say 'no arguments given.';
                    return;
                }
                run_cmd join( ' ', @args );
            },
            DESC => 'runs a system shell command',
            HELP => ['runs a system shell command'],
            DATA => {}
        }
    };

    return ($struct);
}
1;

