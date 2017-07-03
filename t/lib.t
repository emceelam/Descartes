#!/usr/bin/env perl

use warnings;
use strict;
use File::Basename qw(dirname);
use Test::More (tests => 15);
use Descartes::Lib qw(refine_file_name get_share_dir get_config);

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

my $t_dir = dirname(__FILE__);
my $share_dir;
$share_dir = get_share_dir();
ok (-d $share_dir, "$share_dir");
my $dir_handle;
opendir $dir_handle, $share_dir;
my @files = grep { $_ ne '.' && $_ ne '..'} readdir $dir_handle;
closedir $dir_handle;
my @tt_files = grep { m{[.]tt$} } @files;
ok (@tt_files, join (', ', @tt_files) );

my $config = get_config();
ok($config, "get_config()");
is(ref($config), "HASH", "config is hash");
