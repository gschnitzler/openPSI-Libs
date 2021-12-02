package IO::Templates::Meta::Read;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use IO::Templates::Meta::Apply qw(apply_meta);
use IO::Templates::Meta::Parse qw(parse_meta);

our @EXPORT_OK = qw (read_meta);

###############################################################################

# a convenience function
sub read_meta ( $meta_path, $file_tree ) {

    $meta_path =~ s/\/$//;
    my $parsed_meta = parse_meta( $meta_path, $file_tree );
    my $meta_tree = apply_meta( $file_tree, $parsed_meta );
    return $meta_tree;
}