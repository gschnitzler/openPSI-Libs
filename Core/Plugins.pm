package Core::Plugins;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Merge qw(add_tree);
use PSI::Console qw(print_table print_line);
use IO::Config::Check qw(dir_exists);

use Core::Module::Read qw(read_module);
use Core::Module::Load qw(load_module);
use Core::Query qw(query);
use Core::Plugins::Cmds qw (load_cmds);
use Core::Plugins::Macros qw (load_macros);
use Core::Plugins::Scripts qw (load_scripts);
use Core::Plugins::Data qw(plugin_data);

our @EXPORT_OK = qw(load_plugins);

sub _import_plugins ( $debug, @toload ) {

    my @plugins = ();

    foreach my $plugin (@toload) {

        die 'ERROR: no plugin path given'   if !exists( $plugin->{path} ) || !$plugin->{path};
        die 'ERROR: no plugin config given' if !exists( $plugin->{data} ) || ref $plugin->{data} ne 'HASH';
        die "ERROR: Could not find $plugin->{path}" unless ( dir_exists $plugin->{path} );

        print_table( 'Reading Packages from:', $plugin->{path}, ': ' ) if ($debug);

        my $modules_toload = read_module( $debug, $plugin->{path} );

        foreach my $module ( $modules_toload->@* ) {

            print_table( 'Loading Packages from: ', $module, ': ' ) if ($debug);
            my $loaded_plugin = load_module($module);
            $loaded_plugin->{loaded_data} = $plugin->{data};
            push @plugins, $loaded_plugin;
            say 'OK' if ($debug);
        }
    }
    return @plugins;
}

sub _plugin_loader ( $core, $p ) {

    my $name           = $p->{name};
    my $requested_data = $p->{data};                   # optional, data requested by plugin loader from plugin data
    my $loaded_data    = query( $p->{loaded_data} );
    my $state          = $core->{state};
    my $debug          = $core->{CONFIG}->('DEBUG');

    print_table 'Loading Plugin: ', $name, ": ->\n" if ($debug);

    # set up data
    my $plugin_data = plugin_data( $state, $loaded_data, $requested_data );
    my $plugin      = $p->{loader}->( $debug, $plugin_data );
    my $dispatch    = {
        state => sub ($plugin_state_tree) {
            add_tree( $state, $plugin_state_tree ) unless keys $plugin_state_tree->%* == 0;
        },
        scripts => sub ($plugin_scripts_tree) {
            my $scripts = load_scripts( $debug, $state, $loaded_data, $plugin_scripts_tree );
            add_tree( $core->{cmds}, $scripts );
        },
        macros => sub ($plugin_macros_tree) {
            my $macros = load_macros( $core, $plugin_macros_tree );
            add_tree( $core->{cmds}, $macros );
        },
        cmds => sub ($plugin_cmd_list) {
            my $cmds = load_cmds(
                $debug,
                {
                    state      => $state,
                    data       => $loaded_data,
                    structures => $plugin_cmd_list
                }
            );
            add_tree( $core->{cmds}, $cmds );
        }
    };

    # state has to be integrated first, as other plugin sections will depend on it
    $dispatch->{state}->( delete $plugin->{state} );

    foreach my $key ( keys $plugin->%* ) {

        die "ERROR: unsupported plugin data: $key" unless exists( $dispatch->{$key} );
        my $plugin_import_section = delete $plugin->{$key};
        $dispatch->{$key}->($plugin_import_section);
    }

    print_table 'Loaded Plugin: ', $name, ": OK\n" if ($debug);
    return 1;
}

sub _load_plugins ( $core, @plugins_toload ) {

    my $debug = $core->{CONFIG}->('DEBUG');

    print_line 'Loading Plugins' if ($debug);

    my $loaded_plugins = $core->{LOADED_APPS};
    my @plugins        = _import_plugins( $debug, @plugins_toload );

    # to prevent endless loops
    my $counter = scalar @plugins;
    $counter = $counter * $counter;

    while ( my $plugin = shift @plugins ) {

        my $plugin_name = $plugin->{name};
        my $skip        = 0;

        # check if requirements are met
        foreach my $require ( $plugin->{require}->@* ) {

            unless ( exists( $loaded_plugins->{$require} ) ) {
                push @plugins, $plugin;
                $skip++;
                $counter--;
                last;
            }
        }

        die "ERROR: could not resolv dependencies\n", Dumper $loaded_plugins, \@plugins if ( $counter <= 0 );
        next if ($skip);
        $loaded_plugins->{$plugin_name} = _plugin_loader( $core, $plugin );
    }

    print_line('Plugins Successfully Loaded') if ($debug);
    say '' if ($debug);
    return;
}

## frontend
sub load_plugins ( $core, @plugins_toload ) {

    _load_plugins( $core, @plugins_toload );

    # check for modifications
    $core->{ID}->($core);
    return;
}

1;
