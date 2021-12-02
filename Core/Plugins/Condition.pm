package Core::Plugins::Condition;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(plugin_condition);

sub plugin_condition ($definition) {

    return sub ($branch) {

        # return all complete cmds
        if ( ref $branch->[0] eq 'HASH' && scalar keys $branch->[0]->%* > 0 ) {

            # never use while
            foreach my $item ( keys $definition->%* ) {
                my $ref = $definition->{$item};

                return 0 unless ( exists $branch->[0]->{$item} );
                return 0 unless ( ref $branch->[0]->{$item} eq $ref );
            }
            return 1;
        }
        return 0;
    };
}

1;
