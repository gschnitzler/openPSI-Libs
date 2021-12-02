package Tree::Build;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Storable qw(dclone);

use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(build_tree_data build_image_tree);

#####################

# think of this as the reversal of slice_tree.
# it accepts the output of slice_tree and builds a tree. do_leaf is executed on the actual data
sub build_tree_data ( $tree, $do_leaf, @keysets ) {

    foreach my $keyset (@keysets) {

        my $tree_ref     = $tree;
        my $data         = $keyset->[0];
        my $full_path    = $keyset->[1];
        my @path         = ( $full_path->@* );
        my $last_element = pop @path;

        foreach my $key (@path) {

            $tree_ref->{$key} = {} unless ( exists( $tree_ref->{$key} ) );
            $tree_ref = $tree_ref->{$key};
        }
        $tree_ref->{$last_element} = $do_leaf->( $tree_ref->{$last_element}, $data, $full_path );
    }

    return $tree;
}

###########################################################
# this is used by plugins and not really a generic function.
# should get moved to a specific library.

sub _truncate_tree ( $tree, @args ) {

    my $base = shift @args;
    return $tree unless $base;    # nothing to truncate

    my $cond_imgtree = sub ($branch) {
        return 1 if ( ref $branch->[0] eq 'HASH' && exists( $branch->[0]->{name} ) && $branch->[0]->{name} eq $base );
        return 0;
    };

    my @result = slice_tree( $tree, $cond_imgtree );
    return unless ( $result[0]->[0] );
    return { $base => $result[0]->[0] };
}

sub build_image_tree ( $images, $filter, $base ) {

    my $img_tree = {};

    # find parent images first
    foreach my $key ( keys $images->%* ) {

        my $parent = $images->{$key}->{from}->{name};
        $img_tree->{$key} = dclone $images->{$key} if ( !exists $images->{$parent} );
    }

    my @references = ($img_tree);
    while ( my $ref = shift @references ) {
        foreach my $key ( keys $images->%* ) {

            my $image = $images->{$key};
            my $name  = $image->{from}->{name};

            if ( $name && exists( $ref->{$name} ) ) {

                #    $ref->{$name}->{LEAVES}->{$key} = delete $images->{$key};
                #    push @references, $ref->{$name}->{LEAVES};
                push @references, $filter->( $ref->{$name}, $images, $key );
            }
        }
    }

    return _truncate_tree( $img_tree, $base );
}

1;
