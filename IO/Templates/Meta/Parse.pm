package IO::Templates::Meta::Parse;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Carp;

use PSI::Parse::File qw(read_files);
use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);
use IO::Config::Read qw(load_config);
use IO::Config::Check qw(dir_exists);

our @EXPORT_OK = qw (parse_meta convert_meta_paths);

###############################################################################

sub _get_meta_files_from_tree($t) {

    my $meta_files = {};
    my $cond       = sub ($b) {

        return 0 unless ( ref $b->[0] eq '' && $b->[0] eq 'f' && $b->[1]->[-1] =~ /cfmeta$/ );    # find cfmeta files

        my $last_elem = pop $b->[1]->@*;
        my $t_pointer = $t;
        my $m_pointer = $meta_files;

        foreach my $k ( $b->[1]->@* ) {

            $m_pointer->{$k} = {} unless exists $m_pointer->{$k};
            $t_pointer       = $t_pointer->{$k};
            $m_pointer       = $m_pointer->{$k};
        }
        $m_pointer->{$last_elem} = delete $t_pointer->{$last_elem};

        return 1;
    };

    slice_tree( $t, $cond );
    return $meta_files;
}

sub _get_meta_ref ( $ref, $dirname ) {

    my @dirs = split( /\//, $dirname );
    my $file = pop @dirs;

    foreach my $dir (@dirs) {
        $ref->{$dir} = {} unless exists $ref->{$dir};
        $ref = $ref->{$dir};
    }

    return $ref, $file;
}

sub convert_meta_paths($r) {

    my $t = {};
    $t->{_default_meta} = delete $r->{_default_meta} if exists( $r->{_default_meta} );

    foreach my $path ( keys $r->%* ) {

        my $f = {
            flags        => $r->{$path},
            is_dir       => 0,
            is_wildcard  => 0,
            is_recursive => 0,
            k            => '.',           # regular file
        };

        $f->{is_recursive} = 1 if $path =~ s/[*][*]$//;    # recursive implies the $is_dir exp to match
        $f->{is_wildcard}  = 1 if $path =~ s/[*]$//;       # wildcard implies the $is_dir exp to match
        $f->{is_dir}       = 1 if $path =~ s/\/$//;
        $f->{k} = '..'   if ( $f->{is_dir} && !$f->{is_wildcard} );    # its a dir only
        $f->{k} = '...'  if ( $f->{is_dir} && $f->{is_wildcard} );     # its a dir, but flags should be valid for files inside
        $f->{k} = '....' if ( $f->{is_dir} && $f->{is_recursive} );    # its a dir, but flags should be valid for files inside

        # this is to match './*' (original $path). the above regex would reduce this to '.'.
        # we want to remove './' as well as '.'
        die "ERROR: '$path' is not a valid relative path" unless $path =~ s/^[.]\/*//;

        my ( $ref, $file ) = _get_meta_ref( $t, $path );

        if ($file) {
            $ref->{$file}->{ $f->{k} } = $f->{flags};
        }
        else {
            $ref->{ $f->{k} } = $f->{flags};
        }
    }
    return $t;
}

# convert meta files into a tree
sub _parse_meta_files ( $meta_path, $tree ) {

    my $meta = {};
    my $cond = sub ($b) {
        return 0 unless ( ref $b->[0] eq '' && $b->[0] eq 'f' );    # all files

        # read cfmeta file
        my $last_elem = pop $b->[1]->@*;
        my $t_pointer = $tree;
        my $m_pointer = $meta;

        foreach my $k ( $b->[1]->@* ) {
            $t_pointer       = $t_pointer->{$k};
            $m_pointer->{$k} = {} unless exists $m_pointer->{$k};
            $m_pointer       = $m_pointer->{$k};
        }

        $t_pointer->{$last_elem} =
          load_config( [ read_files( join( '/', $meta_path, $b->[1]->@*, $last_elem ) ) ] );    # maybe we need the $loaded cfmeta files later for debugging
        add_tree( $m_pointer, convert_meta_paths( $t_pointer->{$last_elem} ) );                 # anyway, converge loaded cfmeta files
        return 1;
    };

    slice_tree( $tree, $cond );
    return $meta;
}

###############################################################################

sub parse_meta ( $meta_path, $file_tree ) {

    $meta_path =~ s/\/$//;
    confess "ERROR: no such directory $meta_path" if ( !$meta_path || !dir_exists $meta_path );

    # get all meta files from the file tree (and delete them from the file tree)
    # then load the meta files
    return _parse_meta_files( $meta_path, _get_meta_files_from_tree($file_tree) );
}
