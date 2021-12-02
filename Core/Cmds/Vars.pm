package Core::Cmds::Vars;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

# this module is intended to set and unset variables in macros
# can also be used within a shell like IO::Prompter
# variable substitutions are handled internally
##############################################

our @EXPORT_OK = qw(import_vars);

sub _set_var ( $core, @args ) {

    my $key = shift @args;
    my $flat = join( ' ', @args );

    if ( !$key || !$flat ) {
        say 'no key or value given';
        return 1;
    }

    $core->{variables}->{$key} = $flat;
    say 'variable set';
    return 0;
}

sub _unset_var ( $core, $key = 0, @ ) {

    unless ($key) {
        say 'no key given';
        return 1;
    }

    unless ( exists( $core->{variables}->{$key} ) ) {
        say "variable $key is not set";
        return 1;
    }

    delete $core->{variables}->{$key};
    say "variable $key removed";
    return 0;
}

###############################################
# Frontend Functions

sub import_vars ($core) {

    my $struct = {
        set => {
            CMD => sub (@args) {
                shift @args;    #contains $data

                _set_var( $core, @args );
            },
            DESC => 'set variable',
            HELP => [ 'usage:', 'set <key> <value>: sets a key/value pair to replace variables inside a macro' ],
            DATA => {}
        },
        unset => {
            CMD => sub (@args) {
                shift @args;    #contains $data
                _unset_var( $core, @args );

            },
            DESC => 'unset variable',
            HELP => [ 'usage:', 'unset <key>: removes variable' ],
            DATA => {}
        },
        vars => {
            CMD => sub ($data) {
                $Data::Dumper::Indent = 1;
                $Data::Dumper::Terse  = 1;
                say Dumper $core->{variables};
                return;

            },
            DESC => 'view variables',
            HELP => [ 'usage:', 'vars: shows variables' ],
            DATA => {}
        }
    };

    return ($struct);
}
1;

