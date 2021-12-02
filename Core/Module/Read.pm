package Core::Module::Read;

use ModernStyle;
use Exporter qw(import);

use PSI::Parse::File qw(read_files);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(read_module);

sub _read_package ( $file_path ) {

    return if ( !file_exists $file_path|| $file_path !~ m/[.]pm$/x );
    my $file = read_files($file_path);

    return if ( scalar $file->{CONTENT}->@* == 0 );
    foreach ( $file->{CONTENT}->@* ) {
        if (/^\s*package\s+(.*)\;/x) {
            return $1;
        }
    }
    return;
}

# read the contents of a directory without recursion.
sub read_module ($debug, $path) {

    my $modules = [];
    local ($?, $!);
    opendir( my $dh, $path ) or die "ERROR: cannot opendir $path: $!";
    my @files = readdir($dh);
    closedir $dh or die 'ERROR: closing';

    foreach my $file (@files) {
        push $modules->@*, _read_package( join( '/', $path, $file ) );
    }

    say 'OK' if ($debug);
    return $modules;
}

1;