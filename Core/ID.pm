package Core::ID;

use ModernStyle;
use Exporter qw(import);

our @EXPORT_OK = qw(core_id);

sub _get_id ($ref) {
    my $id = scalar $ref;
    $id =~ s/HASH[(](.*)[)]/$1/x;
    return $id;
}

##### frontend
sub core_id($core) {

    my $core_id = _get_id($core);
    return sub($tree) {
        my $id = _get_id($tree);
        die "ERROR: \$tree id was modified, should be $core_id, but is $id" unless ( $core_id eq $id );
    };

}
1;
