package Core::Shell::Input;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

our @EXPORT_OK = qw(filter_input);

sub filter_input ( $line ) {

    chomp $line;

    $line =~ s/#.*//;      # remove comments
    $line =~ s/^\s*//x;    # filter spaces at the beginning and end
    $line =~ s/\s*$//x;    # filter spaces at the beginning and end

    return unless $line; # empty lines

    my @parsed_args = ();
    my @arg         = ();

    # split with () also returns the string in () otherwise excluded, in this case the \s+
    # we need this to maintain the quoted string, but have to remove it for normal args
    foreach my $item ( split( /(\s+)/x, $line ) ) {

        # start of quote
        if ( $item =~ m/^["'](.*)/x ) {
            push @arg, $1;
            next;
        }

        # end of quote
        if ( $item =~ m/(.*)["']$/x ) {
            push @parsed_args, join( '', @arg, $1 );
            @arg = ();
            next;
        }

        # no quote
        if ( scalar @arg == 0 ) {

            next if ( $item =~ m/^\s+$/x ); # ignore whitespace
            push @parsed_args, $item;
        }
        else {
            push @arg, $item; # push whitespace and strings to quoted string
        }
    }

    return @parsed_args;
}

1;
