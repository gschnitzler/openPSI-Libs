package PSI::Tag;

use ModernStyle;
use Exporter qw(import);
use POSIX qw(strftime tzset);

our @EXPORT_OK = qw(get_tag);

sub get_tag () {

    local $ENV{TZ} = 'UTC'; # always use UTC
    tzset;
    return strftime '%y%m%d%H', localtime;
}
