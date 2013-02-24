#!/usr/bin/env perl

# (c) 2013 Piotr Roszatycki <piotr.roszatycki@gmail.com>
#
# GPLv2

use 5.14.0;

use strict;
use warnings;

use Smart::Comments;
use if $ENV{VERBOSE}, 'Carp::Always';

use JSON 'to_json';

use Mojo::DOM;
use Mojo::UserAgent;
use Mojo::URL;
use Mojo::Util qw(trim);

use Encode qw(decode encode);
use Text::Unidecode;


sub url {
    return Mojo::URL->new(shift);
};


my $url_routes_index = url 'http://localhost:5000/rozklady.mpk.krakow.pl/linie.aspx';
my $url_stops_index  = url 'http://localhost:5000/rozklady.mpk.krakow.pl/aktualne/przystan.htm';

my @routes;


use constant {
    ROUTE_TRAM => 0,
    ROUTE_BUS  => 3,
};


sub normalize {
    my ($s) = @_;
    # TODO: $s = decode 'iso-8859-2', $s;
    $s = encode 'utf-8', $s;
    $s = trim $s;
    $s =~ s/\s\s+/ /g;
    return $s;
}

sub id {
    my ($s) = @_;
    $s = unidecode $s;
    $s =~ s/\W+/_/;
    $s =~ tr/a-z/A-Z/;
    return $s;
}

my $data = {
    agency => [
        {
            agency_id => 'MPK',
            agency_name => 'MPK S.A. w Krakowie',
            agency_url => 'http://rozklady.mpk.krakow.pl/',
            agency_timezone => 'Europe/Warsaw',
            agency_lang => 'pl',
        },
    ],
    # TODO: pobieranie kalendarza dla każdej linii z osobna
    calendar => [
        {
            service_id => 'P', 
            monday => 1,
            tuesday => 1,
            wednesday => 1,
            thursday => 1,
            friday => 1,
            saturday => 1,
            sunday => 1,
            start_date => '20130101',
            end_date => '20131231',
        },
    ],
    calendar_dates => [
    ],
};


my %stops_geo;

# Baza geo/krakow.txt z pozycjami przystanów
{
    open my $fh, 'geo/krakow.txt';
    while (my $line = <$fh>) {
        # Agatowa,50.022095,20.041707
        chomp $line;
        my @f = split /,/, $line;
        next unless @f == 3;
        die "Duplicated entry for stop $f[0]" if exists $stops_geo{$f[0]};
        $stops_geo{$f[0]} = { lat => $f[1], lon => $f[2] };
    };
}

my $ua = Mojo::UserAgent->new;
$ua->http_proxy($ENV{http_proxy}) if $ENV{http_proxy};


my %stop_name2id;
# Przystanki
{
    my $dom = $ua->get($url_stops_index)->res->dom;

    $dom->find('li a')->each(sub {
        my ($node) = @_;
        my $href = $node->{href};
        my $stop_name = normalize $node->text;
        my $stop_id = id $stop_name;

        $stop_name2id{$stop_name} = $stop_id;

        die "Missing geo data for stop $stop_name" unless defined $stops_geo{$stop_name};

        return unless $stops_geo{$stop_name};

        push @{$data->{stops}}, {
            stop_id => $stop_id,
            stop_name => $stop_name,
            stop_lat => $stops_geo{$stop_name}{lat},
            stop_lon => $stops_geo{$stop_name}{lon},
        };
    });
}

# Linie
{
    my $dom = $ua->get($url_routes_index)->res->dom;

    $dom->find('td a')->each(sub {
        my ($node) = @_;
        my $href = $node->{href};
        my $route_id = $href =~ s{.*/(.*)/.*}{$1}r;
        my $route_name = normalize $node->text or return;

        return if $route_id > 1; # TODO: na razie tylko jedna linia

        push @routes, {
            id  => $route_id,
            url => $url_routes_index->clone->path($href),
        };

        push @{$data->{routes}}, {
            route_id => $route_id,
            agency_id => 'MPK',  # TODO: hardcode
            route_short_name => $route_name,
            #route_long_name => $route_name,   # TODO: inne niż short_name
            route_type => do {
                if ($route_name =~ /^\d\d?$/) {
                    ROUTE_TRAM;
                }
                else {
                    ROUTE_BUS;
                }
            },
        };
    });
}

# Kursy
{
    foreach my $route (@routes) {
        my $url_route_1 = $route->{url}->clone->path(
            $ua->get($route->{url})->res->dom->find('frame[name="L"]')->[0]->{src}
        );

        my @url_stops;
        my $n1 = 0;

        # Przystanki
        $ua->get($url_route_1)->res->dom->find('li a[target="R"]')->each(sub{
            my ($node) = @_;

            my $stop_name = normalize(eval { $node->b->text } || $node->text);
            ### $stop_name

            my $href = $node->{href};

            my $url_stop = $url_route_1->clone->path($href);

            my $tx = $ua->get($url_stop);
            my $dom = $tx->res->dom;

            my @hours;
            my @times;

            {
                my $n2 = 0;
                $dom->find('td.cellhour:nth-of-type(1) > b > font')->each(sub {
                    my ($node) = @_;
                    $hours[$n2++] = $node->text;
                });
            }

            {
                my $n2 = 0;
                $dom->find('td.cellmin:nth-of-type(2) > font')->each(sub {
                    my ($node) = @_;
                    my @minutes = (grep { /^\d+$/ } split /\s+/, normalize $node->text);
                    push @times, map { sprintf '%02d:%02d:00', $hours[$n2], $_ } @minutes;
                    $n2++;
                });
            }

            {
                my $n2 = 0;
                foreach my $time (@times) {
                    next unless $stop_name2id{$stop_name};  # TODO: warn
                    push @{$data->{stop_times}}, {
                        trip_id => $n2,
                        arrival_time => $time,
                        departure_time => $time,
                        stop_id => $stop_name2id{$stop_name},  # TODO: wyciąganie id z HTML
                        stop_sequence => $n1 + 1,
                    };
                    $n2++;
                }
            }

            # Pierwszy przystanek = lista kursów
            if ($n1 == 0) {
                my $n2 = 0;
                foreach my $time (@times) {
                    push @{$data->{trips}}, {
                        route_id => $route->{id},
                        service_id => 'P',
                        trip_id => $n2,
                    };
                    $n2++;
                }
            }

            $n1++;
        });

        last;
    }
}

# say to_json $data->{stop_times}, { pretty => 1 };

# Dump files

my $fields = {
    agency     => [ qw( agency_id agency_name agency_url agency_timezone agency_phone agency_lang ) ],
    calendar   => [ qw( service_id monday tuesday wednesday thursday friday saturday sunday start_date end_date ) ],
    stops      => [ qw( stop_id stop_name stop_desc stop_lat stop_lon zone_id stop_url ) ],
    routes     => [ qw( route_id agency_id route_short_name route_long_name route_desc route_type route_url route_color route_text_color ) ],
    trips      => [ qw( route_id service_id trip_id trip_headsign direction_id block_id shape_id ) ],
    stop_times => [ qw( trip_id arrival_time departure_time stop_id stop_sequence stop_headsign pickup_type drop_off_time shape_dist_traveled ) ],
};

-d 'data' or mkdir 'data' or die "$!";

foreach my $name (keys %$fields) {
    open my $fh, '>', "data/$name.txt";
    say $fh join ',', @{$fields->{$name}};
    foreach my $row (@{$data->{$name}}) {
        no warnings 'uninitialized';
        say $fh join ',', @$row{ @{$fields->{$name}} };
    };
};

chdir 'data' or die "$!";

unlink 'krakow.zip';
system 'zip', 'krakow.zip', <*.txt>;
