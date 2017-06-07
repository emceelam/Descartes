#!/usr/bin/env perl

use warnings;
use strict;
use Test::More (tests => 5);
use Descartes::Lib qw(refine_file_name);

my $str;
$str = "/tmp/space in file name.jpg";
is (refine_file_name ($str), "space_in_file_name", $str);

$str = "/home/emceelam/descartes/dist.ini";
is (refine_file_name ($str), "dist", $str);

$str = "/home/emceelam/study/perl/env.pl";
is (refine_file_name ($str), "env", $str);

$str = "/home/emceelam/project/descartes/Descartes/lib/Descartes/Lib.pm";
is (refine_file_name ($str), "Lib", $str);

$str = "/home/emceelam/public_html/good_images/gtasa-geographic-1.0.jpg";
is (refine_file_name ($str), "gtasa-geographic-1.0", $str);

