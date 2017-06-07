#!/usr/bin/env perl

use warnings;
use strict;
use Test::More (tests => 11);
use Descartes::Lib qw(refine_file_name);

my $str;
my $refined;
my $suffix;
$str = "/tmp/space in file name.PNG";
($refined, $suffix) = refine_file_name ($str);
is ( "space_in_file_name", "space_in_file_name", $str);
is ($suffix, "png", $suffix);

$str = "/home/emceelam/descartes/dist.ini";
($refined, $suffix) = refine_file_name ($str);
is ($refined, "dist", $str);
is ($suffix, "ini", $suffix);

$str = "/home/emceelam/study/perl/env.pl";
($refined, $suffix) = refine_file_name ($str);
is ($refined, "env", $str);
is ($suffix, "pl", $suffix);

$str = "/home/emceelam/project/descartes/Descartes/lib/Descartes/Lib.pm";
($refined, $suffix) = refine_file_name ($str);
is ($refined, "Lib", $str);
is ($suffix, "pm", $suffix);

$str = "/home/emceelam/public_html/good_images/gtasa-geographic-1.0.jpg";
($refined, $suffix) = refine_file_name ($str);
is ($refined, "gtasa-geographic-1.0", $str);
is ($suffix, "jpg", $suffix);

$refined = refine_file_name ($str);
is ($refined, "gtasa-geographic-1.0", "single parameter scenario");

