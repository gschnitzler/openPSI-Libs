package IO::Config::Check;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;
use Carp;

use PSI::Console qw(print_table);
use Tree::Slice qw(slice_tree);

our @EXPORT_OK = qw(check_config dir_exists file_exists socket_exists link_exists);

my $helper = {
    dircheck       => \&_dircheck,
    filecheck      => \&_filecheck,
    multi_dircheck => \&_multi_dircheck
};

########################

sub _dircheck ($fp) {

    confess 'ERROR: no input, did you forget to add \'\&\' in config definition?' unless $fp;
    return 0 if dir_exists($fp);
    say "unreadable dir $fp";
    return 1;
}

sub _multi_dircheck ( $seperator, $fp ) {

    foreach my $sfp ( split( /$seperator/, $fp ) ) {
        return 1 if ( _dircheck($sfp) );
    }
    return;
}

sub _filecheck ($fp) {

    confess 'ERROR: no input, did you forget to add \'\&\' in config definition?' unless $fp;
    return 0 if ( file_exists $fp );
    say "unreadable file $fp";
    return 1;
}

sub _check_path ( $tree, $path ) {

    my $pointer  = $tree;
    my @cur_path = ( $path->@* );

    while ( my $key = shift @cur_path ) {

        # special case: definition is matched against config, and the config has userdefined entries
        if ( $key eq '*' && $pointer ) {

            foreach my $k ( keys $pointer->%* ) {

                # no need to retain the pointer(s) or care about the state of @cur_path as the forked recursion takes care of the branch
                # error messages get truncated though
                _check_path( $pointer->{$k}, \@cur_path );
            }
            last;
        }
        else {
            $pointer = _check_path_match( $pointer, $key, $path );
        }
    }

    return $pointer; # do not trust a valid pointer to be returned (in case of '*')
}

sub _check_path_match ( $pointer, $key, $path ) {

    return $pointer unless ( ref $pointer eq 'HASH' );

    if ( exists $pointer->{$key} ) {
        $pointer = $pointer->{$key};
    }
    elsif ( exists $pointer->{'*'} ) {
        $pointer = $pointer->{'*'};
    }
    else {
        my $joined_path = join( '->', $path->@* );
        confess "ERROR: entry $joined_path not found";
    }
    return $pointer;
}

sub _check_routines ( $check, $value ) {

    my $onerror = sub ($err) {
        confess 'ERROR: helper returned error' if ($err);
        return;
    };

    # [0] contains the regex
    foreach my $routine ( $check->@[ 1 .. -1 ] ) {    ## no critic (ValuesAndExpressions::ProhibitMagicNumbers )

        if ( exists( $helper->{$routine} ) ) {
            $onerror->( $helper->{$routine}->($value) );
        }
        elsif ( ref($routine) eq 'CODE' ) {
            $onerror->( $routine->($value) );
        }
        else {
            confess "ERROR: unknown helper $routine";
        }
    }
    return;
}

###################### frontend ########
sub dir_exists ($fp) {

    local ( $?, $! );
    return 0 unless $fp;
    return 1 if ( -e $fp and -d $fp and -r $fp );
    return 0;
}

sub file_exists ($fp) {

    local ( $?, $! );
    return 0 unless $fp;
    return 1 if ( -e $fp and -f $fp and -r $fp );
    return 0;
}

sub socket_exists ($fp) {

    local ( $?, $! );
    return 0 unless $fp;
    return 1 if ( -e $fp and -S $fp and -r $fp );
    return 0;
}

sub link_exists ($fp) {

    local ( $?, $! );
    return 0 unless $fp;
    if ( -e $fp and -l $fp and -r $fp ){
        return readlink $fp;
    }
    return 0;
}

sub check_config ( $debug, $p ) {

    print_table( 'Checking Config', $p->{name}, ': ' ) if $debug;
    confess 'ERROR: insufficient parameters' if ( !exists( $p->{name} ) || !exists( $p->{config} ) || !exists( $p->{definition} ) );
    confess 'ERROR: invalid arguments' if ( ref $p->{config} ne 'HASH' || ref $p->{definition} ne 'HASH' || ref $p->{name} || !$p->{name} );

    my ( $name, $cfg, $check, $force_all ) = ( $p->{name}, $p->{config}, $p->{definition}, 0 );

    # with force_all untrue, all the leaves in $cfg are checked for corresponding entries in $check.
    # when force_all is true, the reverse will be tested in addition. so all defined values must exist
    $force_all = 1 if ( exists( $p->{force_all} ) && $p->{force_all} == 1 );

    my $cond = sub ($branch) {
        return 1 if ( ref $branch->[0] ne 'HASH' );
        return 0;
    };

    # for all given values
    foreach my $entry ( slice_tree( $cfg, $cond ) ) {

        my $value       = $entry->[0];
        my $path        = $entry->[1];
        my $joined_path = join( '->', $path->@* );
        my $pointer     = _check_path( $check, $path );

        confess "ERROR: value '$value' of '$joined_path' is invalid" if ( ref($pointer) ne 'ARRAY' || $value !~ $pointer->[0] );
        _check_routines( $pointer, $value );
    }

    # the same for all possible values
    # note that you must not trust the return value of check_path in this case
    if ($force_all) {
        foreach my $entry ( slice_tree( $check, $cond ) ) {
            _check_path( $cfg, $entry->[1] );
        }
    }

    say 'OK' if $debug;
    return $cfg;
}

1;
