package IO::Templates::Update;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use Tree::Search qw(tree_fraction);
use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);
use Tree::Build qw(build_tree_data);

use IO::Templates::Parse qw(check_and_dontdietryingto_fill_template get_variable_tree);
use PSI::Console qw (print_table);

our @EXPORT_OK = qw(update_templates);

#####################################

sub _exception ( $k, @keys ) {

    say join( '->', 'NOTFOUND', @keys );
    return;
}

sub _state_filter($p) {

    # this is effectively a noop for TT. written like this to avoid TT tripping over this when it tries to parse this file
    my @tt_variable = ( '[', '%', ' ', join( '.', $p->{wanted_path}->@* ), ' ', '%', ']' );
    return join( '', @tt_variable );
}

sub _default_filter($p) {

    my ( $data_p, $data_k ) = tree_fraction(
        {
            tree      => $p->{data},
            keys      => $p->{wanted_path},
            exception => \&_exception,
        }
    );

    return if ( !$data_p || !$data_k );

    # handle binary secrets.
    # the trick is simple: the secrets-filter added a key BINARY_SECRET.
    # we rewire the substitutions here and report a binary (1), so the files BASE64 flag is set for the template and its decoded on write
    # note that this is only done here in cfgen.
    if ( ref( $data_p->{$data_k} ) && exists( $data_p->{$data_k}->{BINARY_SECRET} ) ) {
        return $data_p->{$data_k}->{BINARY_SECRET}, 1;
    }
    return $data_p->{$data_k};
}

sub _container_filter($p) {

    my $container_name = $p->{template_path}->[1];
    my $container_tag  = $p->{template_path}->[2];

    #  say 'WP: ', join('->', $p->{wanted_path}->@*);
    #  say 'TP: ', join('->', $p->{template_path}->@*);
    # container config is found in a different place in the actual $data
    my $link_tree->{container} = $p->{data}->{container}->{$container_name}->{$container_tag};

    return _default_filter(
        {
            data        => $link_tree,
            wanted_path => $p->{wanted_path},
        }
    );
}

sub _variable_handler($p) {

    my $filter_on_first_keyword = {

        # container variables do not reference their own names/tags, so they have to be removed from the tree
        container => \&_container_filter,

        # state variables are evaluated at runtime
        state => \&_state_filter,

        # plugin variables are like state variables, but specific to the plugin that uses a template
        plugin => \&_state_filter,
    };

    return $filter_on_first_keyword->{ $p->{wanted_path}->[0] }->($p) if ( exists( $filter_on_first_keyword->{ $p->{wanted_path}->[0] } ) );
    return _default_filter($p);
}

sub _build_substitutions ( $data, $template_path, @wanted_data ) {

    # template variables assume the machine to be root level
    # the template path represents the path of the $data structure,
    # @wanted_data represents the tt variables that are wanted PER MACHINE
    # so give the variable handler the machine as a reference and shift away cluster and machine name

    my $cluster_name = shift $template_path->@*;
    my $machine_name = shift $template_path->@*;
    my $machine_root = $data->{$cluster_name}->{$machine_name};
    my $total_count  = 0;
    my $binary_count = 0;

    foreach my $wanted_variable (@wanted_data) {

        my $wanted_path = $wanted_variable->[1];
        my $bs;    # well, seems like $b is a magic variable in perl. therefor $bs

        ( $wanted_variable->[0], $bs ) = _variable_handler(
            {
                data          => $machine_root,
                wanted_path   => $wanted_path,
                template_path => $template_path,
            }
        );

        $total_count++;
        $binary_count = ( $binary_count + $bs ) if defined $bs;
    }

    die 'ERROR: binary/non-binary variables mixed' if ( $binary_count && $total_count != $binary_count );
    return build_tree_data( {}, sub (@args) { return $args[1] }, @wanted_data ), $binary_count;
}

sub _error($errors) {

    my $error = scalar keys $errors->%*;
    say 'FAILED' if ($error);

    foreach my $variable_name ( sort keys $errors->%* ) {
        print_table( 'Too short/Missing variable', '', ": $variable_name\n" );
    }

    return $error;
}

sub _get_templates($data) {

    # get all templates (this also matches SECRETS, but they are not supposed to container TT variabes)
    # dont match binaries
    my $cond = sub ($branch) {
        return 1 if ref $branch->[0] eq 'HASH' && exists $branch->[0]->{CONTENT} && ( !exists $branch->[0]->{BASE64} || !$branch->[0]->{BASE64} );
        return 0;
    };

    return slice_tree( $data, $cond );
}

# do not allow templates to sport empty variables.
# if you ever want to add optional template variables, find other means
# disabling this check is not what you want
sub _check_empty_leaves($tree) {

    # check for empty leaves
    my $cond = sub ($branch) {

        return if ref $branch->[0];

        if ( !defined( $branch->[0] ) ) {
            my $path = join( '->', $branch->[1]->@* );
            die "ERROR: leaf $path contains undefined value";
        }
        return;
    };
    slice_tree( $tree, $cond );
    return;
}

####
#### side note for future redesigns:
#### if we would add a callback, we could collect all the substitutions from _build_substitution and compile a configset that only contains
#### the config required by a plugin/module/whatever. much like it was intended before.
#### however, right now, this idea was pushed back again in favour of a global config where each (genesis) plugin just requests its needed variables.
sub update_templates ( $data ) {

    my $missed = {};

    print_table( 'Building Templates', ' ', ': ' );

    foreach my $file ( _get_templates($data) ) {

        my ( $substitutions, $base64 ) = _build_substitutions( $data, $file->[1], get_variable_tree( $file->[0]->{CONTENT} ) );

        _check_empty_leaves($substitutions);

        # ignore files that have nothing to substitute
        next if ( !defined($substitutions) || scalar keys $substitutions->%* == 0 );

        my ( $content, @misses ) = check_and_dontdietryingto_fill_template( $file->[0]->{CONTENT}, $substitutions );
        add_tree $missed, @misses;

        $file->[0]->{CONTENT} = $content;
        $file->[0]->{BASE64}  = $base64 if ($base64);

    }
    die 'ERROR: variable check not passed' if _error($missed);
    say 'OK';

    return $data;
}

1;
