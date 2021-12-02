package PSI::Parse::File;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Cwd 'cwd';
use File::Path qw(make_path);
use MIME::Base64;
use Readonly;

use PSI::Console qw(print_table);
use IO::Config::Check qw(dir_exists file_exists);

our @EXPORT_OK = qw(parse_file read_files write_files write_file);

Readonly my $MASK => oct(7777);    # to satisfy perl critic, oct() is used instead of 07777

sub _read_binary ($file_path) {

    my @content = ('# THIS IS BASE64 ENCODED BINARY DATA FROM GENESIS.');
    {
        local $/ = undef;
        open( my $fh, '<', $file_path ) or die "could not open $file_path";
        binmode $fh or print "$? $!";
        push @content, split( /\n/, encode_base64(<$fh>) );
        close $fh or die 'ERROR: closing';
    }
    return \@content;
}

# this is actually nearly twice as fast than using a while <> and doing chomp and s/// there.
sub _read_file($file_path) {

    my @content = ();
    open( my $fh, '<', $file_path ) or die "could not open $file_path";
    @content = <$fh>;
    close $fh or die 'ERROR: closing';

    for (@content) {
        chomp;
        s/\r$//x;
    }
    return \@content;
}

sub read_files (@file_paths) {

    my @files = ();
    local ( $?, $! );

    foreach my $file_path (@file_paths) {

        die "ERROR: file $file_path not found" unless ( file_exists $file_path );
        my $file = {};

        #base64 encode binaries. ignore empty files. -B thinks empty is binary
        if ( !-z $file_path && -B $file_path ) {
            $file->{CONTENT} = _read_binary($file_path);
            $file->{BASE64}  = 1;
        }
        else {
            $file->{CONTENT} = _read_file($file_path);
        }

        $file->{CHMOD}    = sprintf '%o', ( stat($file_path) )[2] & $MASK;    # CHMOD is optional. if its not set, we get CHMOD info from filesystem.
        $file->{LOCATION} = $file_path;

        push @files, $file;
    }
    return wantarray ? @files : $files[0];
}

# well... this generic is outright stupid.
# I conceived it at the very beginning of this project.
# now, its one of the last remaining lines of code from that time together with the parsers that use it.
sub parse_file ( $file, $parser, $parser_flush ) {

    # read in file
    my $file_content   = _read_file($file);
    my $file_structure = {};
    my $heap           = {};

    foreach my $line ( $file_content->@* ) {
        $parser->( $file_structure, $heap, $parser_flush, $line );
    }
    $parser_flush->( $file_structure, $heap );

    return ($file_structure);

}

sub _write_file ( $p ) {

    my $path    = $p->{PATH};
    my $content = $p->{CONTENT};

    my $binmode = ( exists( $p->{BINMODE} ) && $p->{BINMODE} ) ? 1           : 0;
    my $chmod   = ( exists( $p->{CHMOD} )   && $p->{CHMOD} )   ? $p->{CHMOD} : undef;
    my $uid     = ( exists( $p->{UID} )     && $p->{UID} )     ? $p->{UID}   : undef;
    my $gid     = ( exists( $p->{GID} )     && $p->{GID} )     ? $p->{GID}   : undef;

    die 'ERROR: no file given' unless $path;
    die "ERROR: not a file: $path" if $path =~ /\/$/;
    die "ERROR: no content? $path" if ( !$content || ref $content ne 'ARRAY' );

    local ( $?, $! );
    local $/ = undef if $binmode;

    open( my $fh, '>', $path ) or die "ERROR: could not open $path: $? $!";
    binmode $fh or print "$? $!" if $binmode;
    print $fh $content->@*;
    chmod oct($chmod), $fh or die 'ERROR: chmod failed' if $chmod;
    close $fh or die "ERROR: closing $path: $? $!";
    chown $uid, $gid, $path or die "ERROR: chown failed $path: $? $!" if ( $uid && $gid );
    return;
}

##############################################

sub write_file (@files) {

    foreach my $file (@files) {
        _write_file $file;
    }
    return;
}

# this used to be write_template
# there is no connection to the read/parse functions above.
# even the format differs.
sub write_files ( $local_path, $files, $dirs, $print ) {

    die 'ERROR: No files were generated.' unless ( scalar $files->@* );

    foreach my $file ( $files->@* ) {

        my $file_location = $file->{LOCATION};
        my $symlink       = $file->{SYMLINK};
        my $chmod         = $file->{CHMOD};
        my $content       = $file->{CONTENT};
        my ( $uid, $gid ) = ( -1, -1 );    # perl default to don't change
        $uid = $file->{UID} if exists $file->{UID};
        $gid = $file->{GID} if exists $file->{GID};
        my $base64;
        $base64 = $file->{BASE64} if exists $file->{BASE64};

        print_table 'Saving File: ', $file_location, ': ' if ($print);

        die "ERROR: Incomplete Meta Information, cannot write file $file_location"
          if ( !$file_location || !$chmod || !$content || ref $content ne 'ARRAY' );

        $file_location = join( '', $local_path, $file_location );    # substitute absolute path with local path
        $file_location =~ s/[\/]+/\//g;                              # remove extra slashes;
        my $dir = $file_location;

        if ( $dir =~ s/(.*)\/[^\/]+//x ) {
            $dir = $1;
        }
        local ( $?, $! );
        make_path($dir) unless dir_exists $dir;

        if ($symlink) {

            unlink $file_location or print "$? $!" if file_exists $file_location ;    # symlink fails if it was generated before
            symlink( $symlink, $file_location ) or die 'symlink failed';

            # chmod/own does not work with symlinks
        }
        elsif ($base64) {
            shift $content->@*;                                                       # remove the warning added in _binary_read
            write_file(
                {
                    PATH    => $file_location,
                    BINMODE => 1,
                    CONTENT => [ decode_base64( join( '', $content->@* ) ) ],
                    UID     => $uid,
                    GID     => $gid,
                    CHMOD   => $chmod
                }
            );
        }
        else {
            foreach ( $content->@* ) {
                $_ = join( '', $_, "\n" );    # reinsert newlines
            }
            write_file(
                {
                    PATH    => $file_location,
                    CONTENT => $content,
                    UID     => $uid,
                    GID     => $gid,
                    CHMOD   => $chmod
                }
            );
        }
        say 'OK' if ($print);
    }

    foreach my $dir ( $dirs->@* ) {

        my $dir_location = $dir->{LOCATION};
        my $chmod        = $dir->{CHMOD};
        my ( $uid, $gid ) = ( -1, -1 );    # perl default to don't change
        $uid = $dir->{UID} if exists $dir->{UID};
        $gid = $dir->{GID} if exists $dir->{GID};
        $dir_location = join( '', $local_path, $dir_location );    # substitute absolute path with local path
        $dir_location =~ s/[\/]+/\//g;                             # remove extra slashes;
        print_table 'Dir modes: ', $dir_location, ': ' if ($print);
        die "ERROR: Incomplete Meta Information, cannot create dir $dir_location" if ( !$chmod ); # do not check for location. if its empty, its the parent dir.
                                                                                                  #$chmod = join('', '0', $chmod) unless $chmod =~ /^0/;
        local ( $?, $! );

        unless ( dir_exists $dir_location ) {
            make_path($dir_location) or die 'ERROR: make_path failed';
        }
        chmod oct($chmod), $dir_location or die 'ERROR: chmod failed';
        chown $uid, $gid, $dir_location or die 'ERROR: chown failed';

        say 'OK' if ($print);
    }

    return;
}

1;
