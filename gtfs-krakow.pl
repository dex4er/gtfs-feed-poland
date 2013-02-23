#!/usr/bin/env perl

use 5.14.0;
use Modern::Perl;

use JSON 'to_json';
use Smart::Comments;

use Mojo::DOM;
use Mojo::UserAgent;
use Mojo::URL;

use Encode 'decode', 'encode';


my $url_routes_index = Mojo::URL->new('http://rozklady.mpk.krakow.pl/linie.aspx');
my $url_stops_index  = Mojo::URL->new('http://rozklady.mpk.krakow.pl/aktualne/przystan.htm');

my @routes;


use constant {
    ROUTE_TRAM => 0,
    ROUTE_BUS  => 3,
};


sub normalize {
    my $s = encode 'utf-8', decode 'iso-8859-2', shift;
    $s =~ s/\s\s+/ /g;
    $s =~ s/^\s+//;
    $s =~ s/\s$//;
    return $s;
}

my $gtfs_fields = {
    agency     => [ qw( agency_id agency_name agency_url agency_timezone agency_phone agency_lang ) ],
    calendar   => [ qw( service_id monday tuesday wednesday thursday friday saturday sunday start_date end_date ) ],
    stops      => [ qw( stop_id stop_name stop_desc stop_lat stop_lon zone_id stop_url ) ],
    routes     => [ qw( route_id agency_id route_short_name route_long_name route_desc route_type route_url route_color route_text_color ) ],
    trips      => [ qw( route_id service_id trip_id trip_headsign direction_id block_id shape_id ) ],
    stop_times => [ qw( trip_id arrival_time departure_time stop_id stop_sequence stop_headsign pickup_type drop_off_time shape_dist_traveled ) ],
};

my $gtfs_data = {
    agency => [
        {
            agency_id => 'MPK',
            agency_name => 'MPK S.A. w Krakowie',
            agency_url => 'http://rozklady.mpk.krakow.pl/',
            agency_timezone => 'Europe/Warsaw',
            agency_lang => 'pl',
        },
    ],
    # TODO: pobieranie kalendarza
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


# Tymczasowy hack:
# Baza przystanki.txt oraz przystankiwsp.txt z Transportoida
my %stop_name2geo;
{
    my %stop_id2name;
    {
        open my $fh, 'przystanki.txt';
        while (my $line = <$fh>) {
            # 0 Trojadyn Skrzyżowanie
            $line =~ /^(\d+) (.*)$/ or next;
            $stop_id2name{$1} = $2;
        };
    }

    {
        open my $fh, 'przystankiwsp.txt';
        while (my $line = <$fh>) {
            # 0 19868001;50138185;
            $line =~ /^(\d+) (\d{2})(\d{6});(\d{2})(\d{6});$/ or next;
            $stop_name2geo{$stop_id2name{$1}} = { lon => "$2.$3", lat => "$4.$5" }
        };
    }
}


my $ua = Mojo::UserAgent->new;
$ua->http_proxy($ENV{http_proxy}) if $ENV{http_proxy};


my %stop_name2id;
# Przystanki
{
    my $tx = $ua->get($url_stops_index);
    my $dom = $tx->res->dom;

    $dom->find('li a')->each(sub {
        my ($node) = @_;
        my $href = $node->{href};
        my $stop_id = $href =~ s{^p/(.*)\.htm$}{$1}r;
        my $stop_name = normalize $node->text;

        $stop_name2id{$stop_name} = $stop_id;

        # warn "Missing geo data for stop $stop_name" unless defined $stop_name2geo{$stop_name};

        return unless $stop_name2geo{$stop_name};

        push @{$gtfs_data->{stops}}, {
            stop_id => $stop_id,
            stop_name => $stop_name,
            stop_lat => $stop_name2geo{$stop_name}{lat},
            stop_lon => $stop_name2geo{$stop_name}{lon},
        };
    });
}


# Linie
{
    my $tx = $ua->get($url_routes_index);
    my $dom = $tx->res->dom;

    $dom->find('td a')->each(sub {
        my ($node) = @_;
        my $href = $node->{href};
        my $route_id = $href =~ s{.*/(.*)/.*}{$1}r;
        my $route_name = normalize $node->text or return;

        push @routes, {
            id  => $route_id,
            url => $url_routes_index->clone->path($href),
        };

        push @{$gtfs_data->{routes}}, {
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
                    push @{$gtfs_data->{stop_times}}, {
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
                    push @{$gtfs_data->{trips}}, {
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

# say to_json $gtfs_data->{stop_times}, { pretty => 1 };

# Dump files

-d 'data' or mkdir 'data' or die "$!";

foreach my $name (keys %$gtfs_fields) {
    open my $fh, '>', "data/$name.txt";
    say $fh join ',', @{$gtfs_fields->{$name}};
    foreach my $row (@{$gtfs_data->{$name}}) {
        no warnings 'uninitialized';
        say $fh join ',', @$row{ @{$gtfs_fields->{$name}} };
    };
};

chdir 'data' or die "$!";

unlink 'krakow.zip';
system 'zip', 'krakow.zip', <*.txt>;
