package Tree::Merge;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw (dclone);
use Carp;

use InVivo qw(kexists);
use Tree::Slice qw(slice_tree);
use Tree::Build qw(build_tree_data);

our @EXPORT_OK = qw(clone_tree add_tree override_tree query_tree);

#################################################################

my $options = {

    # scalar is a plain SCALAR
    # SCALAR is a SCALAR reference
    # _ref is used to determine which argument ($l or $r) ref should be used

    # there are a few premises.
    # most importantly:
    # - ARRAY and SCALAR must be leaves. so an ARRAY must not contain further REFs
    # for the rest see comments below

    add => {

        # adding means: never override leafes in the old tree
        # therefor, if there is data in $l, return that
        # unlike Hash::Merge, trees from the right are not imported to the left as is.
        # meaning: the root ref of the tree and the leaf data stay as in the original, but the rest of the HASH refs are new
        # so if you have a hashref pointing to somewhere else in the tree, it will point to that junk of the old tree, and not the new one.
        # at the very least, this will cause memory leaks.

        # 2018.02.02 i noticed a bug, where if a scalar $l contained '0' as a value, it would get overridden by $r.
        # but of course that would happen :) so i added a defined(). not sure if it does any good (or bad) for non-scalar.

        _ref => sub ( $l, $r ) {
            return ref $l;
        },
        scalar => sub ( $l, $r ) {
            return $l if defined($l);
            return $r;
        },
        ARRAY => sub ( $l, $r ) {
            return $l if $l;
            return $r;
        },
        CODE => sub ( $l, $r ) {
            return $l if $l;
            return $r;
        },
        HASH => sub ( $l, $r ) {
            return $l if $l;
            return $r;
        },
    },
    override => {    # the same as add, but prefer the right data
        _ref => sub ( $l, $r ) {
            return ref $r;
        },
        scalar => sub ( $l, $r ) {
            return $r;
        },
        ARRAY => sub ( $l, $r ) {
            return $r;
        },
        CODE => sub ( $l, $r ) {
            return $r;
        },
        HASH => sub ( $l, $r ) {
            return $r;
        },

    },
    clone => {    # cloning works on a new empty tree, so there never is data in $l
        _ref => sub ( $l, $r ) {
            return ref $r;
        },
        scalar => sub ( $l, $r ) {
            return $r;
        },
        ARRAY => sub ( $l, $r ) {
            return dclone $r;
        },
        CODE => sub ( $l, $r ) {
            return $r;
        },
        HASH => sub ( $l, $r ) {
            return dclone $r;
        },
    },
    query => {

        # same as clone, but resolve CODE
        # query_tree is used for cloning a tree that has CODE stored within (containing data);
        # its specifically designed for $data to be returned by $query.
        # Storable and Hash::Merge are not up for the task, as they cant handle CODE
        # CODE refs are executed and expected to reveal data.

        _ref => sub ( $l, $r ) {
            return ref $r;
        },
        scalar => sub ( $l, $r ) {
            return $r;
        },
        ARRAY => sub ( $l, $r ) {
            return dclone $r;
        },
        CODE => sub ( $l, $r ) {
            return $r->();
        },
        HASH => sub ( $l, $r ) {
            return dclone $r;
        },
    },
};

foreach my $key ( keys $options->%* ) {
    $options->{$key}->{SCALAR} = sub ( $l, $r ) {
        confess 'ERROR: unexpected data ref type SCALAR';
    };
}

######################################################################################

sub _it_condition_leaves ($branch) {

    my $ref = ref $branch->[0];
    return 1 if ( $ref eq 'ARRAY' || $ref eq 'CODE' || !$ref );      # return all possible leaves
    return 1 if ( $ref eq 'HASH' && keys $branch->[0]->%* == 0 );    # also consider empty hashes as leaves, otherwise they get silently dropped.
    return;
}

sub _build_tree_leafaction ($option_key) {

    confess "ERROR: option key '$option_key' not found in definition" unless kexists( $options, $option_key);
    confess 'ERROR: _ref key not found in definition' unless kexists( $options, $option_key, '_ref' );
    my $option = $options->{$option_key};

    return sub ( $old_data, $new_data, $path ) {

        my $ref = $option->{_ref}->( $old_data, $new_data );
        $ref = 'scalar' if ( !$ref );

        confess "ERROR: unknown data type $ref" unless kexists( $option, $ref );
        return $option->{$ref}->( $old_data, $new_data );
    };
}

# this will add contents from all @updates to the structure of $base;
# it will not override anything in $base, or expand arrays
sub _add_tree ( $type, $base, @updates ) {

    confess 'ERROR: not enough data provided' if ( !$base || scalar(@updates) == 0 );

    foreach my $update (@updates) {

        my @slice = slice_tree( $update, \&_it_condition_leaves );
        build_tree_data( $base, _build_tree_leafaction($type), @slice );    # first we slice the $update into its individual pieces
    }
    return;
}

sub _clone_tree ( $type, @trees ) {

    confess 'ERROR: not enough data provided' if ( scalar @trees == 0 );

    if ( scalar @trees == 1 ) {

        # skip the tree builder (which always returns a hashref), if the data is not a tree
        my $tree_ref = ref $trees[0];
        $tree_ref = 'scalar' unless ($tree_ref);

        return $options->{$type}->{$tree_ref}->( {}, $trees[0] ) unless ( $tree_ref eq 'HASH' );
    }

    my @slice = ();

    foreach my $tree (@trees) {

        confess 'ERROR: non-tree in multiple arguments' if ( ref $tree ne 'HASH' );
        push @slice, slice_tree( $tree, \&_it_condition_leaves );    # reveal all the leaves
    }
    return build_tree_data( {}, _build_tree_leafaction($type), @slice );
}

############## frontends ############################

sub add_tree (@args) {
    _add_tree( 'add', @args );
    return;
}

sub override_tree (@args) {
    _add_tree( 'override', @args );
    return;
}

sub clone_tree (@args) {
    return _clone_tree( 'clone', @args );
}

sub query_tree (@args) {
    return _clone_tree( 'query', @args );
}

1;
__END__
my $base1 = {

    trunk1 => {
        branch1 => {
            leaf1 => {
                array1  => [ 'content1', 'content2' ],
                empty1  => '',
                scalar1 => 'string',
                code1   => sub           { return 'code content' },
            }
        }
    },
    trunk2 => {
        branch2 => {
            leaf2 => {
                array2  => [ 'content1_trunk2', 'content2_trunk2' ],
                empty2  => '',
                scalar2 => 'string2',
                code2   => sub           { return 'code content2' },
            }
        }
    }
};

my $base2 = {

    trunk1 => {
        branch1_1 => {
            leaf1_1 => {
                array1_1  => [ 'content1_base2', 'content2_base2' ],
                empty1_1  => '',
                scalar1_1 => 'string1_1',
                code1_1   => sub           { return 'code content base2' },
            }
        }
    },
    trunk2 => {
        branch2 => {
            leaf2 => {
                array2  => [ 'content1', 'content2' ],
                empty2  => '',
                scalar2 => 'string',
                code2   => sub           { return 'code content2 base2' },
            }
        }
    }
};

say "normal: $base1, $base2";
say Dumper $base1, $base2;

say 'decoded: base1';
say Dumper query_tree($base1);

my $clone = clone_tree($base1);
say "cloned: $clone";
say Dumper $clone;

say "added: $clone, $base2";
add_tree($clone, $base2);
say Dumper $clone;

say "overridden: $clone";
override_tree($clone, $base2);
say Dumper $clone;

say "decoded again: $clone";
say Dumper query_tree($clone);

1;
