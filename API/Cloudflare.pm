package API::Cloudflare;

use ModernStyle;
use Exporter qw(import);
use Data::Dumper;

use MojoX::CloudFlare::Simple;
use Readonly;
use Storable qw(dclone);

use InVivo qw(kexists);
use PSI::Console qw(print_table pad_string);
use Tree::Slice qw(slice_tree);
use Tree::Merge qw(add_tree);

our @EXPORT_OK = qw(list_dns_cloudflare add_dns_cloudflare del_dns_cloudflare supported_types_and_length_cloudflare);

my @supported_types = ( 'A', 'TXT', 'CAA', 'MX' );

# Cloudflare::Simple does not seem to support multi-page answers.
# so we die if the result reaches the maximum of 100 entries
Readonly my $MAX_PER_PAGE => 100;

############################################################

sub _get_handler($domains) {

    my $api = {};

    foreach my $zone_name ( keys $domains->%* ) {

        $api->{$zone_name} = MojoX::CloudFlare::Simple->new(
            email => $domains->{$zone_name}->{USERNAME},
            key   => $domains->{$zone_name}->{API_KEY},
        );
    }
    return $api;
}

sub _error_handler($a) {

    die( 'ERROR: ', Dumper( $a->{errors}, $a->{messages} ) ) if ( scalar $a->{errors}->@* || scalar $a->{messages}->@* || $a->{success} != 1 );

    # result is not always an array. if it is not an array, then its a single answer without pages.
    # like the result of a DELETE request.
    die "ERROR: reached maximum per_page value of $MAX_PER_PAGE ." if ref $a->{result} eq 'ARRAY' && scalar $a->{result}->@* == $MAX_PER_PAGE;
    return $a->{result};
}

sub _check_vars(@args) {

    for my $var (@args) {
        die 'ERROR: undefined variables' unless defined $var;
    }
    return;
}

sub _get_zone_ids( $api ) {

    my $cloudflare = {};
    my @ignored;

    foreach my $zone_name ( keys $api->%* ) {

        print_table 'Query Zone ID', $zone_name, ': ';

        # multiple domains could be handled by a single account.
        # don't query the API if the information is already there
        if ( kexists( $cloudflare, $zone_name, 'ZONEID' ) ) {
            say $cloudflare->{$zone_name}->{ZONEID}, ' (CACHED)';
            next;
        }

        my $zones = _error_handler( $api->{$zone_name}->request( 'GET', 'zones' ) );

        foreach my $zone_entry ( $zones->@* ) {

            my $ze_domain = $zone_entry->{name};
            my $ze_id     = $zone_entry->{id};

            # could be that there are more zones than our configfiles have registered.
            # ignore the extra ones.
            if ( exists $api->{$ze_domain} ) {
                $cloudflare->{$ze_domain}->{ZONEID} = $ze_id;
            }
            else {
                push @ignored, $ze_domain;
            }
        }
        say $cloudflare->{$zone_name}->{ZONEID};
    }

    foreach my $z (@ignored) {
        print_table 'Ignored Zone', $z, ": Not found in config\n";
    }

    return $cloudflare;
}

sub _get_zone_records ( $api, $zoneid, $type ) {

    print_table "Query $type Records", $zoneid, ': ';
    my $zone_records = _error_handler( $api->request( 'GET', "zones/$zoneid/dns_records", { type => $type, per_page => 100 } ) );
    say 'OK (', scalar $zone_records->@*, ')';

    return $zone_records;
}

sub _build_a_tree($records) {

    my $tree = {};
    foreach my $e ( $records->@* ) {

        my $name    = $e->{name};
        my $content = $e->{content};

        #say Dumper $e;

        # only way I found to decode the blessed JSON::PP::Boolean value.
        # without that, the whole key:value pair would just disappear once returned from this module
        # just when you think you have seen it all in perl...
        my $proxied = eval $e->{proxied};    ## no critic

        # each name/content pair should only exist once
        $tree->{$name}->{$content} = {} unless exists( $tree->{$name}->{$content} );
        my $ref = $tree->{$name}->{$content};
        $ref->{type}      = $e->{type};
        $ref->{proxied}   = $proxied;
        $ref->{id}        = $e->{id};
        $ref->{zone_id}   = $e->{zone_id};
        $ref->{zone_name} = $e->{zone_name};
        $ref->{name}      = $e->{name};
        $ref->{content}   = $e->{content};

        #if ( $e->{type} eq 'MX' ) {    # MX records have a priority;
        $ref->{priority} = int( $e->{priority} ) if exists $e->{priority};

        #}

        #if ( $e->{type} eq 'CAA' ) {    # CAA records have additional data, but i think its not used to POST, so ignore it for now
        #    $ref->{data} = dclone $e->{data};
        #}

        #my $string = join(' ', $e->{zone_name}, $e->{type}, $e->{proxied}, $e->{name}, $e->{content});
        #say $string;
        #print_table "$e->{type} $e->{proxied} $e->{zone_name}", $e->{name}, ": $e->{content}\n";
    }

    return $tree;
}

sub _delete_zone_record ( $api, $zone_id, $record_id ) {
    return _error_handler( $api->request( 'DELETE', "zones/$zone_id/dns_records/$record_id", {} ) );
}

sub _add_zone_record ( $api, $zone_id, $args ) {
    return _error_handler( $api->request( 'POST', "zones/$zone_id/dns_records", $args ) );
}

sub _get_records_from_tree($t) {

    my $cond = sub ($b) {
        return 1
          if ref $b->[0] eq 'HASH' && exists( $b->[0]->{zone_id} ) && exists( $b->[0]->{name} ) && exists( $b->[0]->{content} ) && exists( $b->[0]->{id} );
        return 0;
    };

    return slice_tree( $t, $cond );
}

#####################################

sub list_dns_cloudflare ( $keys, @ ) {

    my $api = _get_handler($keys);
    my $dns = _get_zone_ids($api);

    foreach my $zone_name ( keys $api->%* ) {

        for my $type (@supported_types) {
            $dns->{$zone_name}->{$type} = _build_a_tree( _get_zone_records( $api->{$zone_name}, $dns->{$zone_name}->{ZONEID}, $type ) );
        }
    }

    return $dns;
}

sub del_dns_cloudflare ( $keys, $tree ) {

    my $api = _get_handler($keys);
    my $t   = {};

    #my @results = ();

    foreach my $entry ( _get_records_from_tree($tree) ) {

        my $dns_record = $entry->[0];
        my $entry_name = $entry->[1]->[-1];
        my $zone_id    = $dns_record->{zone_id};
        my $zone_name  = $dns_record->{zone_name};
        my $record_id  = $dns_record->{id};
        my $name       = $dns_record->{name};
        my $content    = $dns_record->{content};

        print_table "DEL $name", "$content", ': ';
        _check_vars( $zone_id, $record_id, $name, $content, $zone_name, $api->{$zone_name} );

        #push @results, _delete_zone_record( $api->{$zone_name}, $zone_id, $record_id );
        $t->{$entry_name} = {} unless exists $t->{$entry_name};
        add_tree $t->{$entry_name}, dclone _delete_zone_record( $api->{$zone_name}, $zone_id, $record_id );

        say 'OK';
    }

    return $t;
}

sub add_dns_cloudflare ( $keys, $tree ) {

    # work on a copy, because we update the bogus ids with the real ones, as well as add the API results, and return the tree.
    # the same tree can then be evaluated for errors or used with del_dns_cloudflare to delete entries (thanks to the real ids)
    #my $t       = dclone $tree;
    my $t        = {};
    my $api      = _get_handler($keys);
    my $dns      = _get_zone_ids($api);
    my ($length) = supported_types_and_length_cloudflare();

    #my @results = ();

    foreach my $entry ( _get_records_from_tree($tree) ) {

        my $dns_record  = $entry->[0];
        my $entry_name  = $entry->[1]->[-1];
        my $zone_name   = $dns_record->{zone_name};
        my $zone_id     = $dns_record->{zone_id};
        my $name        = $dns_record->{name};
        my $type        = $dns_record->{type};
        my $content     = $dns_record->{content};
        my $padded_type = pad_string( $type, $length );

        print_table "ADD $padded_type $name", "$content", ': ';
        _check_vars( $zone_name, $zone_id, $name, $type, $content );

        if ( !kexists( $dns, $zone_name, 'ZONEID' ) ) {
            say "IGNORED (zone $zone_name not in config)";
            next;
        }

        # replace zone ids with real zone ids
        $zone_id = $dns->{$zone_name}->{ZONEID};

        #push @results, _add_zone_record( $api->{$zone_name}, $zone_id, $name, $type, $content );
        $t->{$entry_name} = {} unless exists $t->{$entry_name};
        my $args = {
            type    => $type,
            name    => $name,
            content => $content
        };
        $args->{priority} = int( $dns_record->{priority} ) if $type eq 'MX';
        if ( $type eq 'CAA' ) {
            my ( $flags, $tag, $value ) = split( /\s+/, $content );
            $value =~ s/\"//g;
            $args->{data} = {
                flags => int($flags),
                tag   => $tag,
                value => $value
            };
        }
        add_tree $t->{$entry_name}, dclone _add_zone_record( $api->{$zone_name}, $zone_id, $args );

        say 'OK';
    }

    return $t;
}

sub supported_types_and_length_cloudflare() {
    my $length = 0;

    foreach my $e (@supported_types) {
        my $l = length $e;
        $length = $l if $length < $l;
    }
    return $length, @supported_types;
}
1;
