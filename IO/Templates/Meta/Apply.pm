package IO::Templates::Meta::Apply;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Carp;
use Storable qw(dclone);

use Tree::Merge qw(add_tree override_tree);
use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw (apply_meta);

###############################################################################

sub _shift_path($a) {    # remove 'root'
    shift $a->@*;
    return $a->@*;
}

sub _add_file_ref ( $h, @keys ) {

    foreach my $key (@keys) {
        $h->{$key} = {} unless exists $h->{$key};
        $h = $h->{$key};
    }
    return $h;
}

sub _get_dir_ref ( $h, @keys ) {

    foreach my $key (@keys) {
        unless ( exists $h->{$key} ) {
            my $string = join( '/', '.', @keys );
            confess "ERROR: Path element '$key' not found in '$string'";
        }
        $h = $h->{$key};
    }
    return $h;
}

sub _get_defaults_from_tree ( $t, $path ) {

    my $ref      = $t;
    my $defaults = {};

    foreach my $e ( $path->@* ) {

        $ref = $ref->{$e};
        override_tree( $defaults, $ref->{_default_meta} ) if exists $ref->{_default_meta};
    }
    return $defaults;
}

sub _gen_meta_cond($expanded_meta) {

    return sub($b) {
        return 0 unless ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'_default_meta'} );

        my $flags      = $b->[0]->{'_default_meta'};
        my @path       = _shift_path $b->[1];
        my $em_pointer = _add_file_ref( $expanded_meta, @path );
        $em_pointer->{'_default_meta'} = $flags;
        return 1;
    };
}

sub _gen_wildcard_cond ( $files, $expanded_meta ) {

    return sub($b) {
        return 0 unless ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'...'} );

        my $flags      = $b->[0]->{'...'};
        my @path       = _shift_path $b->[1];
        my $dir        = _get_dir_ref( $files, @path );
        my $em_pointer = _add_file_ref( $expanded_meta, @path );

        foreach my $file ( keys $dir->%* ) {

            my $type = $dir->{$file};
            $type = '..' if ref $type eq 'HASH';
            $type = '.'  if $type eq 'f';
            die 'ERROR: unknown file type' unless $type;
            $em_pointer->{$file}->{$type} = {} unless exists $em_pointer->{$file}->{$type};
            add_tree $em_pointer->{$file}->{$type}, $flags;    # only fill in flags that are not there
        }

        return 1;
    };
}

sub _gen_dir_cond ( $files, $expanded_meta ) {

    # copy over explicitly mentioned dirs to new hash
    return sub($b) {
        return 0 unless ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'..'} );

        my $flags = $b->[0]->{'..'};
        my @path  = _shift_path $b->[1];
        my $dir   = pop @path;

        if ($dir) {
            my $em_pointer = _add_file_ref( $expanded_meta, @path );
            _get_dir_ref( $files, @path );    # check if path exists
            $em_pointer->{$dir}->{'..'} = {} unless exists $em_pointer->{$dir}->{'..'};
            override_tree( $em_pointer->{$dir}->{'..'}, $flags );
        }
        else {
            $expanded_meta->{'..'} = {} unless exists $expanded_meta->{'..'};
            override_tree( $expanded_meta->{'..'}, $flags );    # this is for parent root dir
        }

        return 1;
    };
}

sub _gen_file_cond ( $files, $expanded_meta ) {

    return sub($b) {
        return 0 unless ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'.'} );

        my $flags      = $b->[0]->{'.'};
        my @path       = _shift_path $b->[1];
        my $file       = pop @path;
        my $em_pointer = _add_file_ref( $expanded_meta, @path );

        _get_dir_ref( $files, @path );    # check if path exists
        $em_pointer->{$file}->{'.'} = {} unless exists $em_pointer->{$file}->{'.'};
        override_tree( $em_pointer->{$file}->{'.'}, $flags );

        return 1;
    };
}

# resolve all single wildcards to files
sub _expand_wildcard ( $files, $meta ) {

    my $expanded_meta     = {};
    my $default_meta_cond = _gen_meta_cond($expanded_meta);
    my $dir_cond          = _gen_dir_cond( $files, $expanded_meta );
    my $file_cond         = _gen_file_cond( $files, $expanded_meta );
    my $wildcard_cond     = _gen_wildcard_cond( $files, $expanded_meta );

    # add explicitly named files/folders first. order does not matter
    slice_tree( { root => $meta }, $dir_cond );
    slice_tree( { root => $meta }, $file_cond );

    # only now expand wildcards, only adding flags that are not there yet.
    slice_tree( { root => $meta }, $wildcard_cond );
    slice_tree( { root => $meta }, $default_meta_cond );

    return $expanded_meta;
}

sub _gen_recursive_cond ( $expanded_meta, @path ) {

    my $em_pointer_init = _add_file_ref( $expanded_meta, @path );
    my $add_meta        = sub ( $keys, $type, $flags ) {
        _shift_path $keys;
        my $em_pointer = _add_file_ref( $em_pointer_init, $keys->@* );
        $em_pointer->{$type} = {} unless exists $em_pointer->{$type};
        add_tree $em_pointer->{$type}, $flags;
        return;
    };

    return {
        file => sub ( $flags, $b ) {
            return 0 unless ( ref $b->[0] eq '' && $b->[0] eq 'f' );
            $add_meta->( $b->[1], '.', $flags );
            return 1;
        },
        dir => sub ( $flags, $b ) {
            return 0 unless ( ref $b->[0] eq 'HASH' );
            $add_meta->( $b->[1], '..', $flags );
            return 1;
        },
    };
}

# resolve recursive wildcards to files and folders
sub _expand_recursive ( $files, $meta ) {

    my $expanded_meta  = {};
    my $recursive_cond = sub ( $b ) {
        return 0 unless ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'....'} );
        return 1;
    };

    foreach my $e ( slice_tree( { root => $meta }, $recursive_cond ) ) {

        my $flags = delete $e->[0]->{'....'};
        my @path  = _shift_path $e->[1];
        my $dir   = _get_dir_ref( $files, @path );
        my $cond  = _gen_recursive_cond( $expanded_meta, @path );
        slice_tree( { root => $dir }, sub(@a) { $cond->{file}->( $flags, @a ) } );
        slice_tree( { root => $dir }, sub(@a) { $cond->{dir}->( $flags, @a ) } );
    }

    add_tree $meta, $expanded_meta;    # do not override tree, some things might be explicitly defined
    return $meta;
}

sub _find_hash($t) {

    return sub($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists $branch->[0]->{$t} );
        return 0;
    };
}

sub _apply_defaults($meta_tree) {

    for my $type ( '.', '..' ) {
        for my $e ( slice_tree( { root => $meta_tree }, _find_hash($type) ) ) {

            my $path = $e->[1];
            my $file = $e->[0];
            add_tree( $file->{$type}, _get_defaults_from_tree( { root => $meta_tree }, $path ) );
        }
    }

    my $cond = sub($b) {
        return 0 unless ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'_default_meta'} );
        delete $b->[0]->{'_default_meta'};
        return 1;
    };

    slice_tree( { root => $meta_tree }, $cond );    # remove all default entries.

    return $meta_tree;
}

###############################################################################

sub apply_meta ( $file_tree, $parsed_meta ) {
    return _apply_defaults( _expand_wildcard( $file_tree, _expand_recursive( $file_tree, $parsed_meta ) ) );
}
