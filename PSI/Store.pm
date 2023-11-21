package PSI::Store;

use ModernStyle;
use Data::Dumper;
use Exporter qw(import);

use PSI::RunCmds      qw(run_cmd);
use IO::Config::Check qw(dir_exists file_exists);

our @EXPORT_OK = qw(store_image load_image);

sub store_image ($p) {

    my $source   = $p->{source};
    my $target   = $p->{target};
    my $filename = $p->{filename};
    my $tag      = $p->{tag};
    my $options  = $p->{options} ? $p->{options} : ' ';

    die 'ERROR: incomplete parameters' if ( !$source || !$target || !$filename || !$tag );
    die "ERROR: no such directory '$source'" unless ( dir_exists $source );
    die "ERROR: no such directory '$target'" unless ( dir_exists $target );

    my $target_string = join( '', $target, '/', $filename, '___', $tag, '.tar.zst' );
    run_cmd("mkdir -p $target");
    run_cmd("rm -f $target_string");
    run_cmd("cd $source && ZSTD_NBTHREADS=0 ZSTD_CLEVEL=6 tar --xattrs -C . $options --zstd -cpf $target_string . && chmod 640 $target_string");
    return;
}

sub load_image ( $source, $target ) {

    die 'ERROR: incomplete parameters' if ( !$source || !$target );
    die "ERROR: no such file '$source'" unless ( file_exists $source );
    run_cmd("mkdir -p $target");
    run_cmd("tar --xattrs --numeric-owner -C $target/ -xpf $source");
    return;
}

1;
