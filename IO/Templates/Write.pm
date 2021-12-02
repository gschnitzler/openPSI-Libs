package IO::Templates::Write;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use PSI::Parse::File qw(write_files);
use IO::Templates::Parse qw(get_template_dirs get_template_files);

our @EXPORT_OK = qw (write_templates);

###########################################
sub write_templates ( $template_path, $templates, $debug ) {

    my @dirs  = get_template_dirs($templates);
    my @files = get_template_files($templates);
    write_files( "$template_path/", \@files, \@dirs, $debug );
    return;
}

1;
