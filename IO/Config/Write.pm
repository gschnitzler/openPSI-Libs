package IO::Config::Write;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

use PSI::Parse::File qw(write_file);
use Tree::Keys qw(query_keys serialize_keys);

our @EXPORT_OK = qw(write_config);

###############################

# output a valid perl module
sub _write_cf ( $path, $name, $data ) {

    my @script =
      ( "package Config::$name;", 'use Exporter qw(import);', "our \@EXPORT_OK = qw($name\_config);", "sub $name\_config () {", 'return (', $data, ');', '}', );

    write_file(
        {
            PATH    => $path,
            CONTENT => [ join( "\n", @script, '' ) ],
            CHMOD   => 600
        }
    );
    return;
}

sub _write_config_loader ( $path, $modules ) {

    my @loader = ();
    push @loader, join( '', 'package Config::Load;',             "\n\n" );
    push @loader, join( '', 'use ModernStyle;',                  "\n" );
    push @loader, join( '', 'use Exporter qw(import);',          "\n\n" );
    push @loader, join( '', 'our @EXPORT_OK = qw(load_config);', "\n\n" );

    foreach my $module ( $modules->@* ) {
        my $func_name = "$module\_config";
        push @loader, join( '', "use Config::$module qw($func_name);", "\n" );
    }

    push @loader, join( '', 'sub load_config () {', "\n\n" );
    push @loader, join( '', 'return ( {',           "\n\n" );

    foreach my $module ( $modules->@* ) {
        my $func_name = "$module\_config()";
        push @loader, join( '', "$module => $func_name,", "\n" );
    }

    push @loader, join( '', '} );', "\n" );
    push @loader, join( '', '}',    "\n\n" );

    write_file(
        {
            PATH    => $path,
            CONTENT => \@loader,
            CHMOD   => 600
        }
    );

    return;
}

sub _write_plugin_loader ( $path, $plugins ) {

    my @file = ();

    push @file, join( '', 'package Config::Plugins;',            "\n\n" );
    push @file, join( '', 'use ModernStyle;',                    "\n" );
    push @file, join( '', 'use Exporter qw(import);',            "\n\n" );
    push @file, join( '', 'use Config::Load qw(load_config);',   "\n\n" );
    push @file, join( '', 'our @EXPORT_OK = qw(plugin_config);', "\n\n" );
    push @file, join( '', '########################',            "\n\n" );
    push @file, join( '', 'my $loaded_config = load_config;',    "\n" );
    push @file, join( '', 'my $config      = {',                 "\n" );

    foreach my $plugin ( $plugins->@* ) {
        next if $plugin eq '..';    # ignore dir mode entries
        push @file,
          join( '', $plugin, ' => {', "\n" ),
          join( '', 'path => "Plugins/', $plugin, '",', "\n" ),
          join( '', 'data => $loaded_config,', "\n" ),
          join( '', '},', "\n" ),;
    }

    push @file, join( '', '};',                                      "\n" );
    push @file, join( '', 'sub plugin_config () {',                  "\n" );
    push @file, join( '', 'my @plugins = ();',                       "\n" );
    push @file, join( '', 'foreach my $k ( keys( $config->%* ) ) {', "\n" );
    push @file, join( '', 'push @plugins, { $config->{$k}->%* };',   "\n" );
    push @file, join( '', '}',                                       "\n" );
    push @file, join( '', 'return @plugins;',                        "\n" );
    push @file, join( '', '}',                                       "\n" );

    write_file(
        {
            PATH    => $path,
            CONTENT => \@file,
            CHMOD   => 600
        }
    );

    return;
}

sub write_config ( $path, $config, $plugins ) {

    # compact output
    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse  = 1;

    foreach my $file ( keys $config->%* ) {

        my $cf                = $config->{$file};
        my $cf_filename       = join( '.', $file, 'pm' );
        my $queries_filename  = join( '.', $file, 'queries' );
        my $keys_filename     = join( '.', $file, 'keys' );
        my $cf_file_path      = join( '/', $path, $cf_filename );
        my $queries_file_path = join( '/', $path, $queries_filename );
        my $keys_file_path    = join( '/', $path, $keys_filename );

        my ( $queries, $key_tree ) = query_keys($cf);
        write_file(
            {
                PATH    => $queries_file_path,
                CONTENT => [ join( "\n", '#This File is used for debugging', serialize_keys($queries), '' ) ],
                CHMOD   => 600
            },
            {
                PATH    => $keys_file_path,
                CONTENT => [ join( "\n", '#This File is used for debugging', Dumper($key_tree), '' ) ],
                CHMOD   => 600
            }
        );

        _write_cf( $cf_file_path, $file, Dumper $cf);
    }
    my $loader_filename  = join( '.', 'Load',    'pm' );
    my $plugin_filename  = join( '.', 'Plugins', 'pm' );
    my $loader_file_path = join( '/', $path,     $loader_filename );
    my $plugin_file_path = join( '/', $path,     $plugin_filename );
    _write_config_loader( $loader_file_path, [ keys $config->%* ] );
    _write_plugin_loader( $plugin_file_path, $plugins );
    return;
}

1;
