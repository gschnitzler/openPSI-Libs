package IO::Config::Read;

use ModernStyle;
use Exporter qw(import);
use File::Find;
use Data::Dumper;
use Carp;

use PSI::Console qw(print_table);
use PSI::Parse::File qw(read_files);
use Tree::Merge qw(add_tree);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(read_config read_config_single read_config_file load_config);

sub _read_config ( $file_path ) {

    return if ( $file_path !~ m/[.]cfgen$/x || !file_exists $file_path);
    my $file = read_files($file_path);

    if ( scalar $file->{CONTENT}->@* == 0 ) {
        print "Warning: Empty File: $file_path";
        return;
    }

    $file->{FILE} = $file_path;
    return $file;
}

sub read_config ( $debug, $path ) {

    my @modules = ();

    print_table( 'Reading Config from:', $path, ': ' ) if ($debug);
    $File::Find::dont_use_nlink = 1;    # cifs does not support nlink
    find( sub { push @modules, _read_config($_) }, $path );
    confess "ERROR: $!" if $!;
    say 'OK' if $debug;

    return \@modules;
}

sub read_config_file ( $debug, $file ) {

    print_table( 'Reading Config from:', $file, ': ' ) if ($debug);
    my $parsed_file = _read_config( $file );
    say 'OK' if ($debug);
    return [ $parsed_file ];
}

sub read_config_single ( $debug, $path ) {

    my @parsed_files = ();
    local ( $!, $? );
    print_table( 'Reading Config from:', $path, ': ' ) if ($debug);

    opendir( my $dh, $path ) || die "ERROR: cannot opendir $path: $!";
    my @files = readdir($dh);
    closedir $dh or die 'ERROR: closing';

    foreach my $file (@files) {
        push @parsed_files, _read_config( join( '/', $path, $file ) );
    }

    say 'OK' if ($debug);
    return \@parsed_files;
}

sub load_config ($pkg_def) {

    my $pkgs = {};

    foreach my $module ( $pkg_def->@* ) {

        # i know string eval is considered bad form.
        # but we are talking about configfiles here that are evaled during bootstrap of the app.
        # perl style hashes in a perl app, where you trust the data (because you wrote it yourself) seemed the saner choice.
        # alternatives would be to parse YAML or JSON and validate it.
        # a lot of abstraction for the same result.
        # plus, then you could not use perl::tidy
        # also the JSON and YAML are mere deratives of perl structures, but look like shit
        my $mod_c  = join( "\n", $module->{CONTENT}->@* );
        my $pkg_cf = eval $mod_c or confess "ERROR: syntax error in $module->{FILE}";    ## no critic (BuiltinFunctions::ProhibitStringyEval)
        add_tree( $pkgs, $pkg_cf );
    }

    return $pkgs;
}

1;
