package PSI::Parse::Packages;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Term::ANSIColor qw(colorstrip color);

use Tree::Iterators qw(array_iterator);
use Tree::Slice qw(slice_tree);
use PSI::Parse::File qw(read_files);
use PSI::Console qw(print_table count_down);
use PSI::RunCmds qw(run_open);
use IO::Config::Check qw(file_exists);

our @EXPORT_OK = qw(assemble_packages read_system_packages read_pkgversion compare_pkgversion);

#############

sub _read_package ($pkg_content) {

    my $option_regex = qr/([^=]+)=([^\s]+)/x;
    my $sections     = {
        flags       => [],
        post        => [],
        pre         => [],
        package     => [],
        description => [],    # this is a comment section and will be ignored
        options     => {},
    };

    my $section_pointer = '';

    # split sections
    foreach my $line ( $pkg_content->@* ) {

        if ( $line =~ /^\s*\#@([^\s]+)\s*(.*)/x ) {

            my $section         = $1;
            my $section_options = $2;

            #            say "section: $section, options: $section_options";
            die "ERROR: unknown section $section" unless ( exists( $sections->{$section} ) );

            $section_pointer = $sections->{$section}; # update section pointer

            # add section options
            foreach my $option ( split( /\s+/, $section_options ) ) {
                $sections->{options}->{$section}->{$1} = $2 if ( $option =~ $option_regex );
            }
            next;
        }

        next unless ($section_pointer);
        push $section_pointer->@*, $line;
    }

    # package defaults
    my $pkg = {
        enabled    => 0,
        pre_group  => 10,
        post_group => 10,
        pre        => $sections->{pre},
        post       => $sections->{post},
        emerge     => [],
    };

    # override default flags
    foreach my $flag ( $sections->{flags}->@* ) {

        #        say "flag: $flag";
        $pkg->{$1} = $2 if ( $flag =~ $option_regex );
    }

    # override default options
    foreach my $section_name ( keys $sections->{options}->%* ) {

        my $section_options = $sections->{options}->{$section_name};

        foreach my $section_option_name ( keys $section_options->%* ) {

            my $section_option_value = $section_options->{$section_option_name};
            my $pkg_option_name      = join( '_', $section_name, $section_option_name );
            $pkg->{$pkg_option_name} = $section_option_value;
        }
    }

    return unless ( $pkg->{enabled} );

    if ( $sections->{package} ) {

        foreach my $line ( $sections->{package}->@* ) {

            $line =~ s/\s*\#.*//x;    # x requires \#

            #next if ($line =~ m/^\s*#/);
            next if ( $line eq '' );
            push $pkg->{emerge}->@*, $line;
        }
    }

    return $pkg;
}

sub _categorize_packages ( $old_packages, $new_packages ) {

    my $unchanged = {};
    my $new       = {};
    my $changed   = {};

    foreach my $name ( keys( $new_packages->%* ) ) {

        if ( exists( $old_packages->{$name} ) ) {

            my $installed = delete( $old_packages->{$name} );
            my $version   = $installed->{version};
            my $useflags  = $installed->{useflags};

            if ( $new_packages->{$name}->{version} eq $version && $new_packages->{$name}->{useflags} eq $useflags ) {
                $unchanged->{$name} = { version => $version, useflags => $useflags };
            }
            else {
                $changed->{$name} = [ $version, $new_packages->{$name}->{version}, $useflags, $new_packages->{$name}->{useflags} ];
            }
        }
        else {
            $new->{$name} = $new_packages->{$name};
        }
    }
    return $unchanged, $new, $changed;
}

sub _print_unchanged ($unchanged) {

    #say 'Unchanged Packages:';
    foreach my $name ( keys( $unchanged->%* ) ) {

        my $version = $unchanged->{$name}->{version};

        #my $useflags = $unchanged->{$name}->{useflags};
        print_table( $name, $version, ': ' );
        say 'Unchanged';
    }
    return;
}

sub _print_removed ($old_packages) {

    #say 'Removed Packages:';
    foreach my $name ( keys( $old_packages->%* ) ) {

        my $version = $old_packages->{$name}->{version};
        print_table( $name, $version, ': ' );
        say 'Removed';
    }
    return;
}

sub _print_new ($new) {

    foreach my $name ( keys( $new->%* ) ) {

        my $version = $new->{$name}->{version};
        print_table( $name, $version, ': ' );
        say 'New';
    }
    return;
}

sub _print_changed ($changed) {

    say 'Changed Packages:';
    foreach my $name ( keys( $changed->%* ) ) {

        my @old_version = split( //,    $changed->{$name}->[0] );
        my @new_version = split( //,    $changed->{$name}->[1] );
        my @old_use     = split( /\s+/, $changed->{$name}->[2] );
        my @new_use     = split( /\s+/, $changed->{$name}->[3] );    ## no critic (ValuesAndExpressions::ProhibitMagicNumbers)
        my @removed_use = ();
        my @added_use   = ();
        my $old_use_h   = {};
        my $new_use_h   = {};

        foreach my $e (@old_use) {
            $old_use_h->{$e} = 0;
        }

        foreach my $e (@new_use) {
            $new_use_h->{$e} = 0;
        }

        foreach my $k ( keys( $old_use_h->%* ) ) {
            push( @removed_use, $k ) unless ( exists( $new_use_h->{$k} ) );
        }

        foreach my $k ( keys( $new_use_h->%* ) ) {
            push( @added_use, $k ) unless ( exists( $old_use_h->{$k} ) );
        }

        my @highlighted_new_version = ();
        my $version_it              = array_iterator( \@old_version, \@new_version );

        while ( my ( $o_elm, $n_elm ) = $version_it->() ) {

            # values might be '0', so simple unless does not suffice
            $o_elm = '' if ( !$o_elm && !length $o_elm );
            $n_elm = '' if ( !$n_elm && !length $n_elm );

            if ( $o_elm eq $n_elm ) {
                push( @highlighted_new_version, $n_elm );
            }
            else {
                push( @highlighted_new_version, color('red'), $n_elm, color('reset') );
            }
        }

        my $version_string = join( ' => ', join( '', @old_version ), join( '', @highlighted_new_version ) );
        my $use_string     = join( ' ', 'Removed:', color('red'), @removed_use, color('reset'), 'Added:', color('red'), @added_use, color('reset') );
        print_table( $name, $version_string, ": $use_string\n" );

        #say 'Changed';
    }
    return;
}

############################################################

sub read_pkgversion ($pkgversion_f) {

    print_table( 'Reading ', $pkgversion_f, ': ' );

    unless ( file_exists $pkgversion_f ) {
        say 'Missing';
        return;
    }

    my $package_list = {};
    my $file         = read_files($pkgversion_f);
    foreach my $entry ( $file->{CONTENT}->@* ) {
        my ( $name, $version, $mask, @useflags ) = split( /\s+/, $entry );
        $package_list->{$name} = { version => $version, mask => $mask, useflags => join( ' ', @useflags ) };
    }
    say 'OK';
    return $package_list;
}

sub compare_pkgversion ( $old_packages, $new_packages ) {

    my ( $unchanged, $new, $changed ) = _categorize_packages( $old_packages, $new_packages );

    _print_unchanged($unchanged);
    _print_removed($old_packages);
    _print_new($new);
    _print_changed($changed);
    return;
}

sub read_system_packages () {

    my $world_f    = '/var/lib/portage/world';
    my $equery_cmd = 'equery list \'*\' --format=\'$cp $fullversion $mask2\' | grep -v \'^virtual\'';

    print_table( 'Reading @world', ' ', ': ' );
    my $installed_packages = read_files($world_f);
    say 'OK';

    print_table( 'Reading Versions', ' ', ': ' );
    my @eqlist = run_open $equery_cmd;
    say 'OK';

    my $package_list = {};
    my @pkgversion   = ();

    foreach my $entry (@eqlist) {
        my ( $name, $version, $mask ) = split( /\s+/, $entry );
        $package_list->{$name} = [ $version, colorstrip($mask) ];
    }

    print_table( 'Reading USE flags', ' ', ': ' );
    my $counter = scalar $installed_packages->{CONTENT}->@*;

    foreach my $entry ( $installed_packages->{CONTENT}->@* ) {

        print $counter;

        # for unknown reasons, the equery command below has different output on the console than here.
        # here it only outputs the USE flags. on the console it is embedded in human readable form.
        # lets not complain and move on
        my @sorted = sort run_open("equery uses $entry");

        if ( exists( $package_list->{$entry} ) ) {
            push( @pkgversion, join( ' ', $entry, $package_list->{$entry}->[0], $package_list->{$entry}->[1],, @sorted ) );
        }
        else {
            push( @pkgversion, join( ' ', $entry, 'INVALID' ) );
        }
        $counter = count_down($counter);
    }

    say 'OK';
    return @pkgversion;
}

sub assemble_packages ( $debug, $module_t ) {

    my @script_packages = ();
    my $match_packages  = sub ($branch) {

        # return all complete cmds
        if ( ref $branch->[0] eq 'HASH' ) {

            return if ( scalar keys $branch->[0]->%* == 0 );
            return unless ( exists $branch->[0]->{packages} );
            return 1;
        }
        return;
    };

    # the condition cant match zero depth
    if ( exists( $module_t->{packages} ) ) {
        push @script_packages, [ $module_t, [] ];
    }
    else {
        @script_packages = slice_tree( $module_t, $match_packages );
    }

    foreach my $sp (@script_packages) {

        my $pre_g    = [];
        my $post_g   = [];
        my @emerge   = ('emerge -v');
        my $packages = delete $sp->[0]->{packages};
        my @path     = $sp->[1]->@*;
        my $name     = join( '/', @path );
        $name = '.' unless ($name);    # it might be empty

        print_table( 'Assembling packages', $name, ': ' ) if $debug;

        foreach my $pkg ( keys $packages->%* ) {

            my $package = _read_package( $packages->{$pkg}->{CONTENT} );
            next unless $package;

            # say Dumper $package;
            # say "REAL: $pkg $package->{post_group} $package->{post}";
            push( $pre_g->[ $package->{pre_group} ]->@*,   $package->{pre}->@* )    if ( exists( $package->{pre} )    && $package->{pre} );
            push( $post_g->[ $package->{post_group} ]->@*, $package->{post}->@* )   if ( exists( $package->{post} )   && $package->{post} );
            push( @emerge,                                 $package->{emerge}->@* ) if ( exists( $package->{emerge} ) && $package->{emerge} );
        }

        my @pre  = ();
        my @post = ();

        for ( $pre_g->@* ) {
            push @pre, $_->@* if ($_);
        }

        for ( $post_g->@* ) {
            push @post, $_->@* if ($_);
        }

        @emerge = ('# nothing to process') if ( scalar @emerge == 1 );
        @pre    = ('# nothing to process') if ( scalar @pre == 0 );
        @post   = ('# nothing to process') if ( scalar @post == 0 );

        my $joined_emerge = join( ' ', @emerge );
        my $current       = $module_t;

        foreach my $key (@path) {
            $current = $current->{$key};
        }
        $current->{emerge_pre} = {
            CONTENT => \@pre,
            CHMOD   => '755'
        };

        $current->{emerge_post} = {
            CONTENT => \@post,
            CHMOD   => '755'
        };

        $current->{emerge_pkg} = {
            CONTENT => [$joined_emerge],
            CHMOD   => '755'
        };

        say 'OK' if $debug;
    }

    # say Dumper $module_t;
    return $module_t;
}
1;
