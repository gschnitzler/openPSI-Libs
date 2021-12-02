package IO::Templates::Meta::Build;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use File::Find;
use Readonly;
use Carp;

use IO::Config::Check qw(dir_exists);

our @EXPORT_OK = qw (build_meta);

Readonly my $MASK => oct(7777);    # to satisfy perl critic, oct() is used instead of 07777

###################################################################################################

sub _get_defaults_sorted($count) {
    my $defaults = {};

    # set them as default
    foreach my $flag ( keys $count->%* ) {

        # get the most common flags, the or is used when there is to same $v, we then chose to sort rank by name
        # this is to get the same result on every run
        my ($v) = reverse sort { $count->{$flag}->{$a} <=> $count->{$flag}->{$b} or $a cmp $b } keys $count->{$flag}->%*;
        $defaults->{$flag} = $v;
    }
    return $defaults;
}

sub _get_defaults($cfmeta ) {

    my $count = {};

    foreach my $k ( keys $cfmeta->%* ) {
        my $p = $cfmeta->{$k};
        foreach my $flag ( keys $p->%* ) {
            my $v = $p->{$flag};
            if ( exists $count->{$flag}->{$v} ) {
                $count->{$flag}->{$v}++;
            }
            else {
                $count->{$flag}->{$v} = 1;
            }
        }
    }

    return _get_defaults_sorted($count);
}

sub _remove_defaults_from_tree ( $cfmeta, $defaults ) {

    # remove them from the tree
    foreach my $flag ( keys $defaults->%* ) {
        my $default = $defaults->{$flag};
        my $cond    = sub($b) {

            if ( ref $b->[0] eq 'HASH' && exists $b->[0]->{$flag} && $b->[0]->{$flag} eq $default ) {
                delete $b->[0]->{$flag};
                return 1;
            }
            return 0;
        };
        slice_tree( $cfmeta, $cond );
    }
    return;
}

sub _convert_meta_to_cfmeta($meta) {

    my $cfmeta       = {};
    my $convert_cond = sub($t) {
        return sub($b) {
            return 1 if ( ref $b->[0] eq 'HASH' && exists $b->[0]->{$t} );
            return 0;
        };
    };
    my $convert_dispatch = {
        '.' => sub(@a) {
            foreach my $e (@a) {
                shift $e->[1]->@*;    # remove 'root'
                my $p = join( '/', '.', $e->[1]->@* );
                my $h = delete $e->[0]->{'.'};
                $cfmeta->{$p} = $h;
            }
        },
        '..' => sub(@a) {
            foreach my $e (@a) {
                shift $e->[1]->@*;    # remove 'root'
                my $p = join( '/', '.', $e->[1]->@*, '' );
                my $h = delete $e->[0]->{'..'};
                $cfmeta->{$p} = $h;
            }
        },
        '...' => sub(@a) {
            foreach my $e (@a) {
                shift $e->[1]->@*;    # remove 'root'
                my $p = join( '/', '.', $e->[1]->@*, '*' );
                my $h = delete $e->[0]->{'...'};
                $cfmeta->{$p} = $h;
            }
        },

        #'....'=>sub(@a) {
        #    foreach my $e (@a){
        #        my $p = join('/', '.', $e->[1]->@*, '**') ;
        #        my $h = delete $e->[0]->{'...'};
        #        $cfmeta->{$p}=$h;
        #    }
        #},
    };

    for my $t ( keys $convert_dispatch->%* ) {
        $convert_dispatch->{$t}->( slice_tree( { root => $meta }, $convert_cond->($t) ) );
    }
    return $cfmeta;
}

sub _build_cfmeta ( $wanted_flags, $template_path ) {

    my @fs     = ();
    my $cfmeta = {};

    # get a list of all files and subfolders
    $File::Find::dont_use_nlink = 1;    # cifs does not support nlink
    find(
        sub {
            local ( $?, $! );           # because file find?
            my $file = $_;
            my $path = $File::Find::dir;
            return if ( $file eq '.' || $file eq '..' || $file =~ /cfmeta$/ );

            $path =~ s/^$template_path//;    # relative only
            $path =~ s/^[.]\///;             # remove ./
            $path =~ s/^\///;                # remove / # dont be clever here. there is a reason for 2 regex
            $file = "$file/" if ( dir_exists $file );

            if ($path) {
                push @fs, join( '/', $path, $file );
            }
            else {
                push @fs, join( '/', $file );
            }
        },
        $template_path
    );

    # read all info from FS, build a cfmeta like tree
    foreach my $item (@fs) {
        $cfmeta->{"./$item"}->{CHMOD} = sprintf '%o', ( stat("$template_path/$item") )[2] & $MASK if exists $wanted_flags->{CHMOD};
        $cfmeta->{"./$item"}->{UID}   = ( stat("$template_path/$item") )[4]                       if exists $wanted_flags->{UID};
        $cfmeta->{"./$item"}->{GID}   = ( stat("$template_path/$item") )[5]                       if exists $wanted_flags->{GID};
    }
    return $cfmeta;
}

###################################################################################################

# quick and dirty way of building a sample cfmeta file
sub build_meta ( $wanted_flags, $template_path ) {

    die 'ERROR: this does not work. we need to get a list of files as read_template does for read_meta';
    $template_path =~ s/\/$//;

    confess "ERROR: no such directory $template_path" if ( !$template_path || !dir_exists $template_path );
    my $cfmeta = _build_cfmeta( $wanted_flags, $template_path );

    # note: if certain flags are weighted the same, either one will be chosen
    # different defaults lead to different trees. so results might vary
    # if defaults are processed after wildcard permissions, it might lead to more compact trees.
    # but it would require attention on each level and make things  needlessly complicated.
    # weird folder structures should be handwritten anyway.
    my $defaults = _get_defaults($cfmeta);    # find the most common flags
    _remove_defaults_from_tree( $cfmeta, $defaults );

    # parse this with read meta
    $cfmeta->{ROOT} = $template_path;
    my $meta_tree = read_meta( $template_path, $cfmeta );

    # find all directories.
    my $find_dir = sub($b) {
        if ( ref $b->[0] eq 'HASH' && exists $b->[0]->{'..'} ) {
            return 1;
        }
        return 0;
    };

    # set a root '..' so that the below code triggers, even if there are no subdirectories
    # this should be replaced with valid info from the parent dir
    $meta_tree->{'..'} = {};

    foreach my $dir ( slice_tree( { root => $meta_tree }, $find_dir ) ) {

        my $h        = $dir->[0];
        my $wc_count = {};

        # find most common flags
        foreach my $e ( keys $h->%* ) {

            my $f = $h->{$e};
            next unless exists $f->{'.'};    # only work on files

            foreach my $flag ( keys $f->{'.'}->%* ) {
                my $v = $f->{'.'}->{$flag};
                if ( exists $wc_count->{$flag}->{$v} ) {
                    $wc_count->{$flag}->{$v}++;
                }
                else {
                    $wc_count->{$flag}->{$v} = 1;
                }
            }
        }

        $h->{'...'} = _get_defaults_sorted($wc_count);    # set them as wildcard default for the dir

        # remove those flags from files in the directory
        foreach my $e ( keys $h->%* ) {

            my $f = $h->{$e};
            next unless exists $f->{'.'};                 # only work on files

            foreach my $flag ( keys $f->{'.'}->%* ) {
                delete $f->{'.'}->{$flag} if ( $h->{'...'}->{$flag} eq $f->{'.'}->{$flag} );
            }
            delete $h->{$e} if ( scalar keys $f->{'.'}->%* == 0 );    # remove all files without any flags. they are now covert by defaults and wildcard dirs
        }
        delete $h->{'..'} if ( scalar keys $h->{'..'}->%* == 0 );     # remove all dirs without any flags, if there is a wildcard
    }

    my $cfmeta_new = _convert_meta_to_cfmeta($meta_tree);             # convert this back to cfmeta format
    $cfmeta_new->{_default_meta} = $defaults;                         # read defaults

    return $cfmeta_new;
}
