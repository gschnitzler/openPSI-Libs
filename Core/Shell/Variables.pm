package Core::Shell::Variables;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(replace_variables);

sub replace_variables ( $variables, $args ) {

    foreach my $word ( $args->@* ) {

        if ( $word =~ /§(.*)/x ) {

            my $var = $1;
            unless ( exists( $variables->{$var} ) ) {
                say "variable '$var' is not set";
                return 1;
            }
            $word = $variables->{$var};
        }
    }

    return 0;
}

1;
