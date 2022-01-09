package IO::Templates::Read;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Console qw(print_table);
use PSI::Parse::File qw(read_files);
use PSI::Parse::Dir qw(get_directory_tree);
use Tree::Slice qw(slice_tree);

use IO::Templates::Meta::Read qw(read_meta);

our @EXPORT_OK = qw (read_templates convert_meta_structure);

###########################################

sub _create_file_structure ( $doread, $root, $path_to_file ) {

    # remove leading ./
    # keep files with ^. though.
    $path_to_file =~ s/^.\///;
    my $absolute_path = join( '/', $root, $path_to_file );
    my $file          = ($doread) ? read_files($absolute_path) : {};    # create a hash with all required details. lowercase entries are used internally

    # we don't want the location/chmod of the files on the devop machine
    delete $file->{LOCATION};
    delete $file->{CHMOD};

    $file->{absolute_path}        = $absolute_path;
    $file->{relative_folders}->@* = split( '/', $path_to_file );         ## no critic
    $file->{name}                 = pop $file->{relative_folders}->@*;

    return $file;
}

sub _read_templates_from_meta ( $doread, $path, $meta ) {

    # $r reference to $file
    # $v value of meta key
    my $dispatch = {
        LOCATION => sub ( $r, $v ) {
            $r->{LOCATION} = $v;
        },
        SYMLINK => sub ( $r, $v ) {
            $r->{SYMLINK} = $v;
            $r->{CHMOD}   = '777';
        },
        CHMOD => sub ( $r, $v ) {
            $r->{CHMOD} = $v unless ( exists( $r->{SYMLINK} ) );    # set CHMOD, unless its a SYMLINK. in which case its safe to ignore
        },
        UID => sub ( $r, $v ) {
            $r->{UID} = $v;
        },
        GID => sub ( $r, $v ) {
            $r->{GID} = $v;
        },
        BASE64 => sub ( $r, $v ) {
            $r->{BASE64} = $v;
        },
        IGNORE => sub ( $r, $v ) { # added just for completeness
            $r->{IGNORE} = $v;
        },
        CONTENT => sub (@) {
            die 'ERROR: illegal keyword CONTENT';
        }
    };
    my $templates = {};
    my $cond      = sub ($branch) {    # find files
        return 1 if ( ref $branch->[0] eq 'HASH' && exists $branch->[0]->{'.'} );
        return 0;
    };

    for my $e ( slice_tree( $meta, $cond ) ) {

        my $relative_path_to_file = join( '/', '.', $e->[1]->@* );
        my $flags                 = $e->[0]->{'.'};
        next if exists $flags->{IGNORE};
        my $f = _create_file_structure( $doread, $path, $relative_path_to_file );

        for my $entry ( keys $flags->%* ) {

            die "ERROR: invalid entry in meta file: $entry" unless ( exists( $dispatch->{$entry} ) );
            $dispatch->{$entry}->( $f, $flags->{$entry} );
        }

        # LOCATION is also optional. subsystems may have reasons to omit it (header and footer files, dynamic paths etc)
        # however, if SYMLINK is specified, LOCATION is not optional.
        die 'ERROR: no LOCATION given for SYMLINK' if ( exists( $f->{SYMLINK} ) && !exists( $f->{LOCATION} ) );

        # make an entry into $templates
        my $ref = $templates;
        foreach my $dir ( $f->{relative_folders}->@* ) {
            $ref->{$dir} = {} unless exists $ref->{$dir};
            $ref = $ref->{$dir};
        }

        # last node is the filename itself
        die "ERROR: file already read: $f->{absolute_path}" if exists( $ref->{ $f->{name} } );
        $ref->{ $f->{name} } = $f;     # don't assign $ref = $f, the ref to $templates will be overwritten with a ref to $f
        $ref = $ref->{ $f->{name} };

        # remove all entries that are not needed anymore
        foreach my $key ( keys $ref->%* ) {
            delete $ref->{$key} if ( !exists( $dispatch->{$key} ) );
        }
    }

    # now add dir info. stick to '..'
    # all direct and indirect users of templates must be aware of the syntax.
    my $dir_cond = sub ($b) {
        return 1 if ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'..'} && !exists $b->[0]->{'..'}->{IGNORE} );
        return 0;
    };

    for my $e ( slice_tree( { root => $meta }, $dir_cond ) ) {

        shift $e->[1]->@*;    # remove 'root'

        # make an entry into $templates
        my $ref = $templates;
        foreach my $dir ( $e->[1]->@* ) {
            $ref->{$dir} = {} unless exists $ref->{$dir};
            $ref = $ref->{$dir};
        }
        $ref->{'..'} = $e->[0]->{'..'};
    }
    return $templates;
}

###############################################################
# the actual format returned differs from the returned meta format. template only has '..' for dirs.
# meta has '.' for files too'
sub read_templates ( $debug, $template_path ) {

    $template_path =~ s/\/$//;

    # as File::Find is very slow on CIFS, lets get all files first, and then just use that.
    print_table( 'Reading files from ', $template_path, ': ' ) if ($debug);
    my $file_tree = get_directory_tree($template_path);
    say 'OK' if ($debug);

    print_table( 'Reading meta from ', $template_path, ': ' ) if ($debug);
    my $meta = read_meta( $template_path, $file_tree );
    say 'OK' if ($debug);

    print_table( 'Reading templates from ', $template_path, ': ' ) if ($debug);
    my $templates = _read_templates_from_meta( 1, $template_path, $meta );
    say 'OK' if ($debug);

    return ($templates);
}

# this is used to convert a meta structure into a template structure, without actually reading any files from disk.
# such a tree can be used to override templates
sub convert_meta_structure($tree) {
    return _read_templates_from_meta( 0, '', $tree );
}

1;
