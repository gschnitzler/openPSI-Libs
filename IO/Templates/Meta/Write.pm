package IO::Templates::Meta::Write;

# Package Name and Namespace are a bit misleading. 
# This Package works on meta trees, thus the namespace for the lack of a better fit,
# and meta_chownmod 'writes' the stored mode and owner flags to the FS.
# well. Here it is.

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Slice qw(slice_tree);
use IO::Config::Check qw(dir_exists);

our @EXPORT_OK = qw(meta_chownmod);

####################################################################

sub _set_chown ( $full_path, $modes ) {

    my ( $uid, $gid ) = ( -1, -1 );
    $uid = $modes->{UID} if ( exists $modes->{UID} );
    $gid = $modes->{GID} if ( exists $modes->{GID} );
    chown $uid, $gid, $full_path or print "Warning: Chown: $full_path: $!";
    return;
}

sub _set_chmod ( $full_path, $chmod ) {
    $chmod = "0$chmod";
    chmod oct($chmod), $full_path or print "Warning: Chmod: $full_path: $!";
    return;
}

####################################################################
# works on meta trees (not template trees)
# applies permission to existing files on disk.
# roughly the same as write_templates/write_files does, but with meta trees as source, and to existing files on disk

sub meta_chownmod ( $t, $prefix ) {

    die 'ERROR: prefix is not a path' if ( $prefix !~ /\/$/ || !dir_exists $prefix );
    
    my $cond = sub($b) {    # find all files and folders
        return 0 if ref $b->[0] ne 'HASH';
        return 1 if ( exists $b->[0]->{'.'} || exists $b->[0]->{'..'} );
        return 0;
    };

    for my $e ( slice_tree( { root => $t }, $cond ) ) {

        shift $e->[1]->@*; # remove 'root'
        my $path = join( '/', $e->[1]->@* );
        my $full_path = join( '', $prefix, $path );
        my $modes;
        $modes = $e->[0]->{'.'}  if exists $e->[0]->{'.'};
        $modes = $e->[0]->{'..'} if exists $e->[0]->{'..'};
        _set_chown( $full_path, $modes ) if ( exists $modes->{UID} || exists $modes->{GID} );
        _set_chmod( $full_path, $modes->{CHMOD} ) if ( exists $modes->{CHMOD} );
    }
    return;
}
1;