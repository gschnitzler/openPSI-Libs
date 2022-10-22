package API::ACME2;

use ModernStyle;
######################################
use Crypt::Perl::ECDSA::Generate;
use Crypt::OpenSSL::RSA;
use Crypt::OpenSSL::Random;
use Crypt::Perl::PKCS10;
use Crypt::Perl::PK;

#use HTTP::Tiny;
use Net::ACME2::LetsEncrypt;
######################################
use Storable qw(dclone);
use Readonly;
use Data::Dumper;
use Exporter qw(import);

use InVivo qw(kexists kdelete);
use PSI::Console qw(print_table print_line);
use PSI::RunCmds qw(run_open);
use API::Cloudflare qw(add_dns_cloudflare del_dns_cloudflare);
use Tree::Merge qw(add_tree);

our @EXPORT_OK = qw(authorize_domain_acme2 create_accounts);

Readonly my $RSA_KEY_LENGTH => 2048;
my $le_environment = 'production';    # staging for testing, production for use

###############################################################

sub _get_domain_from_wildcard($wildcard) {

    if ( $wildcard =~ s/^[*][.]// ) {
        return $wildcard;
    }
    return;
}

sub _create_key_and_csr ( $wildcard, $ref, @ ) {

    print_table 'Generating Key+CSR', $wildcard, ': ';
    my @dnsname = ($wildcard);
    my $domain  = _get_domain_from_wildcard($wildcard);

    push @dnsname, $domain if $domain;

    my $key    = Crypt::OpenSSL::RSA->generate_key($RSA_KEY_LENGTH);
    my $pkcs10 = Crypt::Perl::PKCS10->new(
        key     => Crypt::Perl::PK::parse_key( $key->get_private_key_string() ),
        subject => [ commonName => $wildcard, ],

        # for a wildcard cert to also match its root domain name, it has to be added here
        attributes => [ [ 'extensionRequest', [ 'subjectAltName', map { ( dNSName => $_ ) } @dnsname ], ], ],
    );

    $ref->{SSL_PRIV} = $key->get_private_key_string();
    $ref->{SSL_CSR}  = $pkcs10->to_pem();

    say 'OK';
    return;
}

sub _check_cloudflare_zone ( $cloudflare_keys, $zone ) {

    print_table 'Zone has Cloudflare Key', $zone, ': ';
    if ( exists $cloudflare_keys->{$zone} && $cloudflare_keys->{$zone} ) {
        say 'OK';
        return $cloudflare_keys->{$zone};
    }

    say 'No (Ignoring)';
    return;
}

sub _check_letsencrypt_zone ( $le_keys, $zone ) {

    print_table 'Zone has LetsEncrypt Key/ID', $zone, ': ';
    if ( kexists( $le_keys, $zone, 'ID' ) && kexists( $le_keys, $zone, 'KEY' ) && $le_keys->{$zone}->{ID} && $le_keys->{$zone}->{KEY} ) {
        say 'OK';
        return $le_keys->{$zone};
    }

    say 'No (Ignoring)';
    return;
}

sub _create_le_obj ( $environment, $ct, $at, $zone ) {

    print_table 'Init LetsEncrypt Instance', $zone, ': ';
    $ct->{$zone}->{LE}->{ACME} = Net::ACME2::LetsEncrypt->new(
        environment => $environment,
        key         => $ct->{$zone}->{LE}->{KEY},
        key_id      => $ct->{$zone}->{LE}->{ID}
    );
    say 'OK';
    return {};
}

sub _get_txt_update ( $ct, $at, $zone ) {

    print_table 'Prepare TXT records', $zone, ': ';

    my $zone_branch = $ct->{$zone};
    my $domains     = $zone_branch->{DOMAINS};
    my $updates     = {};

    foreach my $domain ( sort keys $domains->%* ) {

        foreach my $challenge ( $domains->{$domain}->{LE_CHALLENGE}->@* ) {

            my $txt_domain = $challenge->[1];
            my $txt_value  = $challenge->[2];

            # txt_value is used, because the txt_domain is the same for every subdomain, and there can of course be multiple records
            $updates->{$txt_value} = {
                zone_name => $zone,
                zone_id   => 'bogus',
                id        => 'bogus',
                name      => $txt_domain,
                type      => 'TXT',
                content   => $txt_value
            };
        }
    }

    say 'OK';
    return $updates;
}

sub _create_le_order ( $wildcard, $ref, $cf, $le ) {

    print_table 'Create Order', $wildcard, ': ';
    my @domains = ($wildcard);
    my $domain  = _get_domain_from_wildcard($wildcard);
    push @domains, $domain if $domain;

    my $order  = $le->{ACME}->create_order( identifiers => [ map { { type => 'dns', value => $_ } } @domains ], );
    my @authzs = map { $le->{ACME}->get_authorization($_) } $order->authorizations();

    $ref->{LE_AUTHZS} = \@authzs;
    $ref->{LE_ORDER}  = $order;

    say 'OK';
    return;
}

sub _get_le_challenge ( $wildcard, $ref, $cf, $le ) {

    print_table 'Challenges', $wildcard, ': ';

    my $domain  = _get_domain_from_wildcard($wildcard);
    my $c_count = 0;
    $wildcard = $domain if $domain;

    for my $authz ( $ref->{LE_AUTHZS}->@* ) {

        my $zone = $authz->identifier()->{'value'};
        my ( $challenge, @rest ) = grep { $_->type() eq 'dns-01' } $authz->challenges();
        my $txt_domain = $challenge->get_record_name();
        my $txt_record = $challenge->get_record_value( $le->{ACME} );

        $txt_domain = join( '.', $txt_domain, $wildcard );
        $c_count++;

        push $ref->{LE_CHALLENGE}->@*, [ $challenge, $txt_domain, $txt_record ];

    }

    say $c_count;
    return;
}

sub _wait_on_dns ( $wildcard, $ref, $cf, $le ) {

    print_table 'Wait on DNS Update', $wildcard, ': ';
    for my $c ( $ref->{LE_CHALLENGE}->@* ) {
        _lookup_txt( $c->[1], $c->[2] );
    }

    say 'OK';
    return;
}

sub _accept_le_challenge ( $wildcard, $ref, $cf, $le ) {

    print_table 'Accept Challenge', $wildcard, ': ';
    for my $c ( $ref->{LE_CHALLENGE}->@* ) {
        $le->{ACME}->accept_challenge( $c->[0] );
    }

    say 'OK';
    return;
}

sub _wait_on_le_status ( $wildcard, $ref, $cf, $le ) {

    _wait_on_authorization( $le->{ACME}, $ref->{LE_AUTHZS}->@* );
    return;
}

sub _issue_le_order ( $wildcard, $ref, $cf, $le ) {

    print_table 'Issue Order', $wildcard, ': ';
    my $order = $ref->{LE_ORDER};
    my $csr   = $ref->{SSL_CSR};
    $le->{ACME}->finalize_order( $order, $csr );
    say 'OK';

    while ( $order->status() ne 'valid' ) {
        print_table 'LetsEncrypt Cert Order Status', $wildcard, ': ';
        $le->{ACME}->poll_order($order);
        say $order->status();
        sleep 1;
    }
    return;
}

sub _download_cert ( $wildcard, $ref, $cf, $le ) {

    print_table 'Downloading Cert', $wildcard, ': ';
    $ref->{SSL_CERT} = $le->{ACME}->get_certificate_chain( $ref->{LE_ORDER} );
    say 'OK';
    return;
}

sub _dump_ssl ( $export, $wildcard, $ref, $cf, $le ) {

    my ( $cert, @chain ) = split( /\n\n/s, $ref->{SSL_CERT} );
    $export->{$wildcard} = {
        CERT         => $cert,
        PRIV         => $ref->{SSL_PRIV},
        INTERMEDIATE => join( "\n\n", @chain )
    };
    return;
}

sub _create_acme_tree ( $cloudflare_keys, $letsencrypt_keys, $ct, $at, $zone, $domain ) {

    my $wc       = join( '', '*.', $domain );
    my $ssl_type = $ct->{$zone}->{$domain};
    my $domain_t = {};
    my $ssl      = {
        SSL_PRIV         => '',
        SSL_CSR          => '',
        SSL_CERT         => '',
        SSL_INTERMEDIATE => '',
        LE_AUTHZS        => [],
        LE_ORDER         => '',
        LE_CHALLENGE     => [],

    };

    # 0 means host only
    # 1 means wildcard
    # 2 means host & wildcard

    if ( $ssl_type == 0 ) {
        $domain_t->{$domain} = dclone $ssl;
    }
    elsif ( $ssl_type == 1 ) {
        $domain_t->{$wc} = dclone $ssl;
    }
    else {
        $domain_t->{$domain} = dclone $ssl;
        $domain_t->{$wc}     = dclone $ssl;
    }

    return {
        $zone => {
            CF => { $cloudflare_keys->{$zone}->%* },
            LE => {
                $letsencrypt_keys->{$zone}->%*,
                ACME => ''    # the Net::ACME2 object
            },
            DOMAINS => { $domain_t->%* }
        }
    };
}

sub _lookup_txt ( $domain, $wanted_value ) {

    while (1) {

        foreach my $value ( run_open "host -t txt $domain || true" ) {

            if ( $value =~ /[^"]+"([^"]+)"/ ) {
                my $v = $1;
                return if $v eq $wanted_value;
            }
        }
        sleep 2;
    }
    return;
}

sub _wait_on_authorization ( $acme, @queue ) {

    # less stupid version of the reference example

    while ( my $authz_obj = shift @queue ) {

        my $status = $acme->poll_authorization($authz_obj);
        my $name   = $authz_obj->identifier()->{'value'};

        substr( $name, 0, 0, '*.' ) if $authz_obj->wildcard();

        print_table 'LetsEncrypt Status', $name, ': ';

        if ( $status eq 'invalid' ) {
            my ($challenge) = grep { $_->type() eq 'dns-01' } $authz_obj->challenges();
            say 'INVALID';
            say Dumper $challenge;
            die "$name authorization is in $status state.";
        }

        if ( $status eq 'pending' ) {

            push @queue, $authz_obj;
            sleep 1;
            say 'PENDING';
        }
        say 'PASSED' if ( $status eq 'valid' );
    }

    return;
}

sub _do_per_zone ( $current_tree, $action ) {

    my $altered_tree = {};
    foreach my $zone ( sort keys $current_tree->%* ) {
        add_tree $altered_tree, $action->( $current_tree, $altered_tree, $zone );
    }
    return $altered_tree;
}

# dont use this on the acme tree, use _update_acme instead, or _do_per_zone
sub _do_per_domain ( $current_tree, $action ) {

    my $altered_tree = {};
    foreach my $zone ( sort keys $current_tree->%* ) {
        foreach my $domain ( sort keys $current_tree->{$zone}->%* ) {
            add_tree $altered_tree, $action->( $current_tree, $altered_tree, $zone, $domain );
        }
    }
    return $altered_tree;
}

sub _update_acme ( $tree, $action ) {

    foreach my $zone ( sort keys $tree->%* ) {

        my $zone_branch = $tree->{$zone};
        my $domains     = $zone_branch->{DOMAINS};

        foreach my $domain ( sort keys $domains->%* ) {
            $action->( $domain, $domains->{$domain}, $zone_branch->{CF}, $zone_branch->{LE} );
        }
    }
    return;
}

sub create_accounts ( $domains, $lets_encrypt_accounts ) {

    my $tree = _do_per_zone(    # create base tree
        $domains,
        sub ( $ct, $at, $z ) {
            return {
                $z => {
                    'ID'  => '',
                    'KEY' => ''
                },
            };
        }
    );

    _do_per_zone(               # remove existing secrets
        $tree,
        sub ( $ct, $at, $z ) {
            kdelete( $ct, $z, 'KEY' ) if ( kexists( $lets_encrypt_accounts, $z, 'KEY' ) && $lets_encrypt_accounts->{$z}->{KEY} );
            kdelete( $ct, $z, 'ID' )    # ID is only valid if there is a key as well
              if ( kexists( $lets_encrypt_accounts, $z, 'ID' )
                && $lets_encrypt_accounts->{$z}->{ID}
                && kexists( $lets_encrypt_accounts, $z, 'KEY' )
                && $lets_encrypt_accounts->{$z}->{KEY} );
            return {};
        }
    );

    _do_per_zone(                       # remove now empty zones
        $tree,
        sub ( $ct, $at, $z ) {
            my $has_keys = 'No';
            print_table 'Zone has keys', $z, ': ';
            if ( scalar keys $ct->{$z}->%* == 0 ) {
                delete $ct->{$z};
                $has_keys = 'Yes (ignoring)';
            }
            say $has_keys;
            return {};
        }
    );

    _do_per_zone(    # generate domain keys
        $tree,
        sub ( $ct, $at, $z ) {
            return {} unless ( defined kexists( $ct, $z, 'KEY' ) );
            print_table 'Generating Domain key', $z, ': ';
            $ct->{$z}->{KEY} = Crypt::Perl::ECDSA::Generate::by_name('secp384r1')->to_pem_with_curve_name();
            say 'OK';
            return {};
        }
    );

    _do_per_zone(    # create letsencrypt accounts
        $tree,
        sub ( $ct, $at, $z ) {
            return {} unless ( defined kexists( $ct, $z, 'ID' ) );
            print_table 'Create Account', $z, ': ';
            my $acme = Net::ACME2::LetsEncrypt->new(
                environment => $le_environment,
                key         => $ct->{$z}->{KEY},
                key_id      => undef
            );
            my $terms_url = $acme->get_terms_of_service();
            $acme->create_account( termsOfServiceAgreed => 1, );
            $ct->{$z}->{ID} = $acme->key_id();
            say 'OK';
            return {};
        }
    );
    return $tree;
}

###############################################################
#
# prepare operations for everything, then batch execute them
# main reason is to keep API requests to a minimum.
# if you want to test things, use a minimal version of dns.cfgen
sub authorize_domain_acme2 ( $domains, $cloudflare_api_keys, $le_account_keys ) {

    print_table 'LetsEncrypt Environment', ' ', ": $le_environment\n";

    _do_per_zone(
        $domains,
        sub ( $ct, $at, $z ) {
            delete $ct->{$z} unless _check_cloudflare_zone( $cloudflare_api_keys, $z );    # remove entries that have no cloudflare keys
            delete $ct->{$z} unless _check_letsencrypt_zone( $le_account_keys, $z );       # remove entries that have no letsencrypt keys
            return {};
        }
    );

    # take the cloudflare api keys, and create a tree we can later expand
    my $tree = _do_per_domain( $domains, sub(@args) { _create_acme_tree( $cloudflare_api_keys, $le_account_keys, @args ) } );

    _update_acme( $tree, \&_create_key_and_csr );                                          # generate ssl priv keys and csrs
    _do_per_zone( $tree, sub(@args) { return _create_le_obj( $le_environment, @args ) } );
    _update_acme( $tree, \&_create_le_order );
    _update_acme( $tree, \&_get_le_challenge );

    my $txt_updates    = _do_per_zone( $tree, \&_get_txt_update );
    my $dns_add_result = add_dns_cloudflare( $cloudflare_api_keys, $txt_updates );

    _update_acme( $tree, \&_wait_on_dns );
    _update_acme( $tree, \&_accept_le_challenge );
    _update_acme( $tree, \&_wait_on_le_status );
    _update_acme( $tree, \&_issue_le_order );
    _update_acme( $tree, \&_download_cert );

    my $dns_del_result = del_dns_cloudflare( $cloudflare_api_keys, $dns_add_result );

    print_line 'SAVING';

    my $ssl_certs = {};
    _update_acme( $tree, sub(@args) { _dump_ssl( $ssl_certs, @args ) } );

    return $ssl_certs;
}

1;
