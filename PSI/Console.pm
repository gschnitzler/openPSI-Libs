package PSI::Console;

use ModernStyle;
use Data::Dumper;
use Exporter qw(import);
use Term::ANSIColor qw(colorstrip);
use Readonly;
use IO::Prompter;

use Tree::Keys qw(query_keys serialize_keys);

our @EXPORT_OK = qw(print_table string_table print_line wait_prompt count_down read_stdin print_structure pad_string);

Readonly my $PADDING       => 5;
Readonly my $LEFT_LENGTH   => 35;
Readonly my $MIDDLE_LENGTH => 45;
Readonly my $TYPE_PADDING  => 8;

my $totallength = $LEFT_LENGTH + $MIDDLE_LENGTH;

sub _print_table ( $l, $middle, $r ) {

    # we can not use printf fixed width with embedded ANSI color codes.
    # so lets hack.

    my $cs_realleftlength   = length colorstrip($l);
    my $realmiddlelength    = length $middle;
    my $cs_realmiddlelength = length colorstrip($middle);
    my $realleftlength      = length $l;

    if ( $cs_realleftlength > $LEFT_LENGTH ) {
        my $diff = $cs_realleftlength - $LEFT_LENGTH + $PADDING;
        $l =~ s/^.{$diff}(.*)/\[\.\.\.\]$1/x;
    }
    else {
        my $diff  = $LEFT_LENGTH - $cs_realleftlength;
        my $spfv  = join( '', $diff, 's' );
        my $fixed = sprintf "%$spfv", '';
        $l = join( '', $l, $fixed );
    }

    if ( $cs_realmiddlelength > $MIDDLE_LENGTH ) {

        my $diff = $cs_realmiddlelength - $MIDDLE_LENGTH + $PADDING;
        $middle =~ s/^.{$diff}(.*)/\[\.\.\.\]$1/x;
    }
    else {
        my $diff  = $MIDDLE_LENGTH - $cs_realmiddlelength;
        my $spfv  = join( '', $diff, 's' );
        my $fixed = sprintf "%$spfv", '';
        $middle = join( '', $fixed, $middle );
    }

    return join( '', $l, $middle, $r );

}

sub print_table (@a) {
    print _print_table(@a);
    return;
}

sub string_table (@a) {
    return _print_table(@a);
}

sub pad_string ( $string, $padding_length ) {

    my $string_length = length $string;
    my @padding       = ();
    while ( $string_length != $padding_length ) {
        push @padding, ' ';
        $string_length++;
    }
    return join( '', @padding, $string );
}

sub print_line ($string) {

    my $length = '';
    $length = length $string if ($string);

    if ( !$length ) {
        print '#' for ( 0 .. $totallength );
        print "\n";
        return;
    }

    my $fillin = $totallength;
    $fillin = $fillin - $length - 2;
    $fillin = $fillin / 2;

    print '#' for ( 0 .. $fillin );
    print " $string ";

    $fillin = $fillin - 1 if ( 0 == $length % 2 );     # if string was even, the devision above resultet in an uneven fillin.

    print '#' for ( 0 .. $fillin );
    print "\n";

    return;
}

### 21.04.2017
### calling prompt from different modules with changing parameters suddenly resulted in segmentation faults.
### Devel::Trace (perl -d:Trace ./genesis.pl) revealed that it died within Contextual::Return
### reinstalling Contextual::Return (IO::Prompter dependency) and installing Term::ReadKey
### (Conway says IO::Prompter works 'much better' with it) fixed the issue
### in the process of debugging, i added this function.
### also switched from -in => *STDIN to -stdio
sub read_stdin ( $prompt, @args ) {

    local ( $!, $? );
    return scalar prompt( $prompt, '-stdio', @args );
}

# add key to abort. so we don't exit shell. or introduce y/n
sub wait_prompt ( $message, $counter ) {

    print $message;
    while ( $counter > 0 ) {

        print $counter;
        sleep 1;
        $counter = count_down($counter);
    }
    return;
}

sub count_down ($counter) {

    my $backspace = $counter;
    my $space     = $counter;

    $backspace =~ s/./\b/xg;
    $space     =~ s/./\ /xg;

    # needed to not only reset the cursor but also to override previously written content
    print $backspace, $space, $backspace;
    $counter--;
    return $counter;
}

sub print_structure($tree) {

    my ( $paths, $keys ) = query_keys($tree);
    say $_ for ( serialize_keys($paths) );
    return;
}

1;
