package Core::Cmds::Exit;

use ModernStyle;
use Exporter qw(import);

# Export
our @EXPORT_OK = qw(import_exit);

# for itself, this command is a noop
# for convenience, a IO::Pompter session could be terminated,
# though its more convenient to just use ^C or ^D
# i can't even image it being useful in a macro, but here it is.

###############################################
# Frontend Functions

sub import_exit () {

    my $struct = {
        exit => {
            CMD  => sub (@) { exit 0; },
            DESC => 'exits with 0',
            HELP => ['exits with 0'],
            DATA => {}
        }
    };
    return ($struct);
}
1;

