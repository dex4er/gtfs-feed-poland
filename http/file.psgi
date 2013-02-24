#!/usr/bin/env starman

use Plack::App::File;
my $app = Plack::App::File->new({ root => ".", content_type => 'text/html', encoding => 'iso-8859-2' })->to_app;
