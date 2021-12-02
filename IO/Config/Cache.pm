package IO::Config::Cache;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Path qw(make_path);

use IO::Config::Check qw(dir_exists);
use IO::Config::Read qw(read_config_file load_config);
use PSI::Parse::File qw(write_file);

our @EXPORT_OK = qw(read_cache write_cache);

sub read_cache ( $debug, $path, @files ) {

    unless ( dir_exists $path ) {
        local ( $!, $? );
        make_path $path or die "ERROR: $! $?";
        return;
    }

    my @cache = ();
    foreach my $file_name (@files) {
        push @cache, load_config( read_config_file( $debug, join( '/', $path, $file_name ) ) );
    }

    return wantarray ? @cache : $cache[0];
}

sub write_cache ( $debug, $path, $files ) {

    local $Data::Dumper::Indent    = 1;
    local $Data::Dumper::Terse     = 1;
    local $Data::Dumper::Quotekeys = 0;
    local $Data::Dumper::Deepcopy  = 1;

    foreach my $file_name ( keys $files->%* ) {
        my $content = $files->{$file_name};

        write_file(
            {
                PATH    => join( '/', $path, $file_name ),
                CONTENT => [ Dumper($content), ";\n" ],
                CHMOD   => 600
            }
        );
    }
    return;
}

1;
