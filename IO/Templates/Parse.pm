package IO::Templates::Parse;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Template;
use Template::Context;

use Tree::Search qw(tree_fraction);
use Tree::Slice  qw(slice_tree);
use Tree::Build  qw(build_tree_data);
use PSI::Console qw(print_table);

our @EXPORT_OK =
  qw(get_template_files get_template_dirs get_variable_tree check_and_fill_template check_and_dontdietryingto_fill_template check_and_fill_template_tree get_directory_tree_from_templates);

###################################################

sub _file_cond ($b) {
    return 1 if ( ref $b->[0] eq 'HASH' && exists( $b->[0]->{CONTENT} ) && exists( $b->[0]->{CHMOD} ) );
    return 0;
}

sub _dir_cond ($b) {
    return 0 if ( $b->[1]->[-1] ne '..' );
    pop $b->[1]->@*;    # remove '..'
    return 1;
}

sub _combine_blocks (@template) {

    my @combined = ();
    my @block    = ();
    my $counter  = {
        start   => 0,
        end     => 0,
        current => ''
    };

    for my $line (@template) {

        if ( $line =~ /^\s*\#\$block\s*(start|end)/x ) {

            my $startend = $1;
            $counter->{current} = $startend;
            $counter->{$startend}++;

            push @block, $line; # include the #$block tags, to withstand multiple _fill_templates passes
            next unless ( $startend eq 'end' );
            push @combined, join( "\n", @block );
            $counter->{current} = '';
            @block = ();
            next;
        }

        if ( $counter->{current} eq 'start' ) {
            push @block, $line;
            next;
        }

        if ( !$counter->{current} ) {
            push @combined, $line;
            next;
        }
    }
    die 'ERROR: uneven start/end block count' unless ( $counter->{start} == $counter->{end} );
    return @combined;
}

sub _fill_template ( $template, $substitutions ) {

    my $template_string = join( "\n", $template->@* );    # convert array to string, TT wants it so
    my @filled_template = ();
    my $template_obj    = Template->new();

    $template_obj->process(
        \$template_string,
        $substitutions,
        sub ($output) {
            @filled_template = _combine_blocks split( /\n/x, $output );    # convert back to array
        }
      )
      or do {
        my $error = $template_obj->error();
        say 'error type: ', $error->type();
        say 'error info: ', $error->info();
        say $error;
      };

    return \@filled_template;
}

sub _check_template ( $template, $substitutions ) {

    my $missing   = {};
    my $toomuch   = {};
    my $exception = sub ( $k, @keys ) {
        my $joined_keys = join( '.', @keys );
        $missing->{$joined_keys} = '';
        return;
    };

    foreach my $wanted_variable ( get_variable_tree($template) ) {

        my ( $ref, $key ) = tree_fraction(
            {
                tree      => $substitutions,
                keys      => $wanted_variable->[1],
                exception => $exception
            }
        );

        if ( defined($ref) && defined($key) && ref( $ref->{$key} ) ) {
            my $joined_keys = join( '.', $wanted_variable->[1]->@* );
            $toomuch->{$joined_keys} = '';
        }
    }
    return ( $missing, $toomuch ) if ( scalar keys $missing->%* != 0 || scalar keys $toomuch->%* != 0 );
    return;
}

sub _get_ref ( $pointer, @keys ) {

    my $last_key = pop @keys;
    foreach my $e (@keys) {
        $pointer->{$e} = {} unless exists $pointer->{$e};
        $pointer = $pointer->{$e};
    }
    return $pointer, $last_key;
}

##############################################
###
### If you ever wonder, why variables prefixed with plugin.* are not replaced properly when they contain an TT conditional (like IF):
### conditionals get resolved at the cfgen stage...
###
##############################################
my $allowed_tt_vmethods = {
    match   => sub ($b) { pop $b->[1]->@*; },
    ttvalue => sub ($b) { pop $b->[1]->@*; }    # this is a TT variable name than can be used inside templates to store values for scripting tt
};

sub get_variable_tree ($array) {

    my $template_string   = join( "\n", $array->@* );                                 # convert array to string, TT wants it so
    my $obj               = Template::Context->new( TRACE_VARS => 1 );                # get a tree of all variables used
    my $compiled          = $obj->template( \$template_string ) or die $obj->error;
    my $substitution_tree = $compiled->variables;

    return slice_tree(
        $substitution_tree,
        sub ($branch) {

            # check for bad quotations
            if ( exists( $branch->[0]->{item} ) ) {
                my $path = join( '.', $branch->[1]->@* );
                die "ERROR: TT::Context does not allow 'item' quotation. variable name up to 'item': '$path'";
            }

            if ( scalar keys $branch->[0]->%* == 0 ) {
                for my $ttv ( keys $allowed_tt_vmethods->%* ) {    # remove special tt vmethods and variables
                    $allowed_tt_vmethods->{$ttv}->($branch) if ( $branch->[1]->[-1] eq $ttv );
                }
                $branch->[0] = join( ' ', $branch->[1]->@* );
                return 1;
            }
            return 0;
        }
    );
}

# acts on a single template
sub check_and_fill_template ( $template, $substitutions ) {

    my ( $missing, $toomuch ) = _check_template( $template, $substitutions );
    return _fill_template( $template, $substitutions ) if ( scalar keys $missing->%* == 0 && scalar keys $toomuch->%* == 0 );

    print_table( 'Missing variable',   '', ": $_\n" ) for ( sort keys $missing->%* );
    print_table( 'Variable too short', '', ": $_\n" ) for ( sort keys $toomuch->%* );

    die 'ERROR: variable check not passed';
}

# same, but used by cfgen to collect errors and give you a summary
sub check_and_dontdietryingto_fill_template ( $template, $substitutions ) {

    my ( $missing, $toomuch ) = _check_template( $template, $substitutions );
    return [], $missing, $toomuch if ( scalar keys $missing->%* != 0 || scalar keys $toomuch->%* != 0 );
    return _fill_template( $template, $substitutions ), $missing, $toomuch;
}

# can handle a whole tree
sub check_and_fill_template_tree ( $tree, $substitutions ) {

    my @missed               = ();
    my @filled_templates     = ();
    my $filled_template_tree = build_tree_data(

        # use $tree instead of {}, in case there is something other than templates in it, so its preserved (like '..')
        # In which case, you have to use this function in scalar context
        $tree,
        sub ( $old_data, $new_data, $path ) {
            push @missed, _check_template( $new_data->{CONTENT}, $substitutions );
            $new_data->{CONTENT} = _fill_template( $new_data->{CONTENT}, $substitutions );

            #$new_data->{PATH} = $path;
            push @filled_templates, $new_data;
            return $new_data;
        },
        slice_tree(
            $tree,
            sub ($b) {
                return 1 if ( ref $b->[0] eq 'HASH' && exists( $b->[0]->{CONTENT} ) && ref( $b->[0]->{CONTENT} ) eq 'ARRAY' );
                return 0;
            }
        )
    );

    for my $missing (@missed) {
        print_table( 'Missing/Too short variable', '', ": $_\n" ) for ( sort keys $missing->%* );
    }
    die 'ERROR: variable check not passed' if ( scalar @missed != 0 );
    return @filled_templates               if (wantarray);
    return $filled_template_tree;
}

sub get_template_dirs ($t) {

    my @dirs = ();

    foreach my $e ( slice_tree( $t, \&_dir_cond ) ) {
        my $dir = $e->[0];
        $dir->{LOCATION} = exists( $dir->{LOCATION} ) ? join( '/', $dir->{LOCATION} =~ s/[\/]$//r, $e->[1]->@* ) : join( '/', $e->[1]->@* );
        push @dirs, $dir;
    }
    return @dirs;
}

sub get_template_files ($t) {

    my @files = ();

    foreach my $entry ( slice_tree( { root => $t }, \&_file_cond ) ) {
        my $file = $entry->[0];
        shift $entry->[1]->@*;    # remove 'root'
        if ( !exists $file->{LOCATION} ) {
            $file->{LOCATION} = join( '/', $entry->[1]->@* );
        }
        elsif ( $file->{LOCATION} =~ s/[\/]$// ) {    # LOCATION was a base path
            $file->{LOCATION} = join( '/', $file->{LOCATION}, $entry->[1]->@* );
        }

        push @files, $file;
    }

    return @files;
}

# see this as equivalent of get_directory_tree from PSI::Parse::Dir
# it takes a template tree, and builds a tree like get_directory_tree does
sub get_directory_tree_from_templates ($tree) {

    my $directory_tree = {};

    foreach my $entry ( slice_tree( { root => $tree }, \&_file_cond ) ) {
        shift $entry->[1]->@*;    # remove 'root'
        my ( $pointer, $file_name ) = _get_ref( $directory_tree, $entry->[1]->@* );
        $pointer->{$file_name} = 'f';
    }
    foreach my $entry ( slice_tree( $tree, \&_dir_cond ) ) {
        my ( $pointer, $last_dir ) = _get_ref( $directory_tree, $entry->[1]->@* );
        next unless $last_dir;                                               # ignore empty location. happens when the '..' of parent dir is resolved
        $pointer->{$last_dir} = 'd' if ( !exists $pointer->{$last_dir} );    # empty dirs have a dir type
    }

    return $directory_tree;
}

1;
