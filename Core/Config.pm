package Core::Config;

use ModernStyle;
use Exporter qw(import);

our @EXPORT_OK = qw(core_config);

########################

sub core_config () {

    return {
        DEBUG      => 0,
        MACROSAVE  => '/tmp/macrosave',
        MACROMOUNT => '/mnt/genesis',
    };
}

1;
