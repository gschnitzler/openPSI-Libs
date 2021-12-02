package PSI::System::BTRFS;

use ModernStyle;
use Data::Dumper;
use Exporter qw(import);
use Readonly;

use InVivo qw(kexists);
use IO::Config::Check qw(dir_exists);
use PSI::Console qw(print_table);
use PSI::RunCmds qw(run_cmd run_open);

our @EXPORT_OK =
  qw( get_btrfs_subvolumes delete_btrfs_subvolume create_btrfs_snapshot create_btrfs_snapshot_simple delete_btrfs_subvolume_simple create_btrfs_subvolume);

Readonly my $BTRFS_PATH => 8;

sub get_btrfs_subvolumes ($dir) {

    run_cmd("mkdir -p $dir");    # $dir needs to exist, otherwise btrfs will fail

    # -a $dir here is required on rescue cds where / is no btrfs volume
    my @subvolumes = run_open "btrfs subvolume list -a $dir";
    my $wanted     = {};
    $dir =~ s/\///x;

    foreach my $line (@subvolumes) {

        next unless ( $line =~ /$dir/x );

        my @match = split( /\s+/x, $line );
        my $path  = $match[$BTRFS_PATH];
        $path =~ s/$dir\///x;

        my ( $image, $tag ) = split( /\//, $path );

        next if ( $image =~ /^<FS_TREE>.*/x );    # ignore root types.
        $wanted->{$tag}->{$image} = { path => join( '', '/', $dir, '/', $image, '/', $tag ), };
    }

    return $wanted;
}

sub create_btrfs_snapshot ($p) {

    my $path       = $p->{path};
    my $target     = $p->{target};
    my $target_tag = $p->{target_tag};
    my $source     = $p->{source};
    my $source_tag = $p->{source_tag};

    delete_btrfs_subvolume( $path, "$target:$target_tag" );
    print_table( 'Creating new Snapshot', "$source:$source_tag ", ": $target:$target_tag\n" );
    run_cmd("mkdir -p $path/$target");
    run_cmd( 'sync', "btrfs subvolume snapshot $path/$source/$source_tag $path/$target/$target_tag > /dev/null" );

    return;
}

sub create_btrfs_subvolume ($p) {

    my $path       = $p->{path};
    my $target     = $p->{target};
    my $target_tag = $p->{target_tag};

    delete_btrfs_subvolume( $path, "$target:$target_tag" );
    print_table( 'Creating new Subvolume', "$target:$target_tag ", ': ' );
    run_cmd("mkdir -p $path/$target");
    run_cmd( 'sync', "btrfs subvolume create $path/$target/$target_tag > /dev/null" );

    say 'OK';
    return;

}

sub delete_btrfs_subvolume ( $dir, @delete ) {

    my $snapshots = get_btrfs_subvolumes($dir);
    foreach my $entry (@delete) {

        my ( $n, $t ) = split( /:/, $entry );
        my $p = ( $t && kexists( $snapshots, $t, $n ) ) ? $snapshots->{$t}->{$n}->{path} : '';

        if ($p) {
            print_table( 'Removing old Snapshot', "$entry ", ': ' );
            run_cmd("btrfs subvolume delete $p > /dev/null");
            say 'OK';
        }
    }
    return;
}

########################### above is for build, below is for backup, had no time to merge and test ################

sub create_btrfs_snapshot_simple ( $source, $target ) {

    delete_btrfs_subvolume_simple("$target$source");
    print_table( 'Creating new Snapshot', "$source ", ": $target\n" );
    run_cmd("mkdir -p $target");
    run_cmd( 'sync', "btrfs subvolume snapshot $source $target > /dev/null" );
    return;
}

sub delete_btrfs_subvolume_simple ($path) {

    if ( dir_exists $path ) {
        print_table( 'Removing old Snapshot', "$path ", ': ' );
        run_cmd("btrfs subvolume delete $path > /dev/null");
        say 'OK';
    }
    return;
}

1;
