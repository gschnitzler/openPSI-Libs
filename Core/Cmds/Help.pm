package Core::Cmds::Help;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Search qw(tree_search_position);
use Tree::Slice qw(slice_tree);

# Export
our @EXPORT_OK = qw(import_help);

###############################################
# Frontend Functions

sub _help ( $core, @args ) {

    if ( scalar @args == 0 ) {

        say "\nKnown Commands:\n";

        my $desc_table = {};

        foreach my $entry (
            slice_tree(
                $core->{cmds},
                sub ($branch) {
                    return 1 if ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{DESC} ) && ref $branch->[0]->{DESC} eq '';
                    return;
                }
            )
            )
        {
            $desc_table->{ join( ' ', $entry->[1]->@* ) } = $entry->[0]->{DESC};
        }

        foreach my $key ( sort keys $desc_table->%* ) {
            printf "%-40s : %s\n", $key, $desc_table->{$key};
        }

        say "\nuse 'help <cmd (full length)>' to view help for a specific command";
    }
    else {
        my ( $cmd, $path, $cmd_args ) = tree_search_position(
            $core->{cmds},
            sub ($branch) {
                return 1 if ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{HELP} ) && ref $branch->[0]->{HELP} eq 'CODE';
                return;
            },
            \@args
        );

        if ( $cmd_args && scalar $cmd_args->@* != 0 ) {
            say '';
            say 'Omitted arguments: ', join( ' ', $cmd_args->@* );
        }

        if ($cmd) {
            say '';
            say foreach $cmd->{HELP}->()->@*;
            say '';
        }
        else {
            say '';
            say 'No help found';
            say '';
        }
    }

    return;
}

sub import_help ($core) {

    my $struct = {
        help => {
            CMD => sub (@args) {
                shift @args;    # contains $query
                _help( $core, @args );
            },
            DESC => 'well, this',
            HELP => [ 'usage:', '\'help\' prints an overview of all known commands', '\'help <a command>\' prints (somewhat) more detailed help' ],
            DATA => {}
        }
    };

    return ($struct);
}
1;

