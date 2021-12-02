package PSI::Parse::Dir;

use ModernStyle;
use File::Find;
use Exporter qw(import);
use Data::Dumper;
use Carp qw(confess);

use IO::Config::Check qw(dir_exists file_exists);

our @EXPORT_OK = qw(get_directory_list get_directory_tree);

sub _file_type($fp) {

    my $type = 0;
    if ( file_exists $fp ) {
        $type = 'f';
    }
    elsif ( dir_exists $fp ) {
        $type = 'd';
    }

    # ignore unknown files. most likely symbolic links or other things we don't want to get involved with
    die "ERROR: unknown filetype for $fp" if ( !$type && !-l $fp );
    return $type;
}

# empty directories are represented as {}
# everything else uses their file type
sub _build_tree(@paths) {

    my $tree = {};

    foreach my $p (@paths) {

        my $type      = shift $p->@*;
        my $last_elem = pop $p->@*;
        my $pointer   = $tree;

        next unless $last_elem;    # root dir;

        foreach my $k ( $p->@* ) {
            $pointer->{$k} = {} unless ( exists $pointer->{$k} );
            $pointer = $pointer->{$k};
        }
        if ( $type eq 'd' ) {
            $pointer->{$last_elem} = {};
        }
        else {
            $pointer->{$last_elem} = $type;
        }
    }
    return $tree;
}

#######################################

sub get_directory_list ($path) {

    local ( $!, $? );
    opendir( my $dh, $path ) or die "could not open dir '$path': $!";
    my @dircontent = readdir($dh);
    closedir $dh or die 'ERROR: closing';

    my $h = {};
    foreach my $entry (@dircontent) {

        next if ( $entry eq '.' || $entry eq '..' );
        my $type = _file_type("$path/$entry");
        $h->{$entry} = $type if $type;
    }
    return $h;
}

# does the same as get_directory_list, but recursively
# types are only added for leaves.
sub get_directory_tree($path) {

    my @paths = ();
    $path =~ s/\/$//;
    $File::Find::dont_use_nlink = 1;    # cifs does not support nlink

    find(
        sub {
            my $f = $_;
            return if $f =~ /^[.].*[.]swp/;    # ignore vim swap files

            my $relative = $File::Find::name;
            my $fp       = $File::Find::name;
            $relative =~ s/^$path\/*//;

            if ( $f eq '.' ) {                 # find's way of reporting dirs
                push @paths, [ 'd', $relative ];
                return;
            }
            my $type = _file_type($fp);
            push @paths, [ $type, split( /\//, $relative ) ] if $type;
            return;
        },
        $path
    );

    #confess "ERROR: $!" if ($!); ignore that.
    $! = undef;                                ## no critic

    return _build_tree(@paths);
}

1;
