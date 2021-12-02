package Core::Module::Load;

use ModernStyle;
use Exporter qw(import);
use Module::Load;

our @EXPORT_OK = qw(load_module);

sub load_module($module) {

    load $module;
    my $plugin = $module->import_hooks();

    die 'ERROR: Plugin has invalid format'
        if ( ref $plugin ne 'HASH'
        || !exists $plugin->{name}
        || !exists $plugin->{require}
        || !exists $plugin->{loader}
        || ref $plugin->{name}
        || ref $plugin->{require} ne 'ARRAY'
        || ref $plugin->{loader} ne 'CODE' );

    return $plugin;
}
1;
