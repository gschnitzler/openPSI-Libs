package Core;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Readonly;

# core default configuration
use Core::Config qw(core_config);
use Core::ID qw(core_id);
use Core::Shell qw(core_shell);
use Core::Plugins qw(load_plugins);
use Core::Plugins::Cmds qw(load_cmds);
use Core::Query qw(query);

use Core::Cmds::Exit qw(import_exit);
use Core::Cmds::System qw(import_system);
use Core::Cmds::View qw(import_view);
use Core::Cmds::Vars qw(import_vars);
use Core::Cmds::Drop qw(import_drop);
use Core::Cmds::Macro qw(import_macro);
use Core::Cmds::Help qw(import_help);

use Tree::Merge qw(add_tree);

our @EXPORT_OK = qw(load_core);

Readonly my $CORE_VERSION => '3.2.0';

##### frontend
sub load_core($config) {

    # fill in unsupplied configuration
    add_tree( $config, core_config );

    my $core = {

        variables => {},    # variables are stored here
        cmds      => {},    # command tree is registered here
        state     => {},    # register state handlers

        LOADED_APPS => {},
        PLUGINS     => {},                # dispatch table of plugins
        CONFIG      => query($config),    # core config
        VERSION     => $CORE_VERSION,

    };
    $core->{ID}    = core_id($core);
    $core->{shell} = core_shell($core);
    $core->{load}  = sub (@plugins) { load_plugins( $core, @plugins ); };

    # load the commands
    my $cmds = load_cmds(
        $config->{DEBUG},
        {   state      => $core->{state},
            data       => $config,
            structures => [

                # all core commands
                # they are the only ones allowed to operate on $core,
                import_exit(),
                import_system(),
                import_view($core),
                import_drop($core),
                import_help($core),
                import_vars($core),
                import_macro($core),
            ]
        }
    );

    # merge imported commands
    add_tree( $core->{cmds}, $cmds );

    return $core;
}
1;
