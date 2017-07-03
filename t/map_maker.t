#!/usr/bin/perl

use warnings;
use strict;

use Cwd qw(cwd abs_path);
use List::MoreUtils qw(any);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(rmtree);
use Descartes::MapMaker;
use Test::More (tests => 24);

my $t_dir       = dirname(__FILE__);
my $testimg_dir = "$t_dir/../testimg";
my $pdf_path    = "$testimg_dir/tandem-bike-riders.pdf",
my $dest_dir    = '/tmp/map_maker.t';

my $map_maker = new Descartes::MapMaker(
  source_file => $pdf_path,
  dest_dir    => $dest_dir,
);

ok ($map_maker, "Descartes::MapMaker object");
is ($map_maker->dest_dir, $dest_dir, "dest_dir: $dest_dir");
is ($map_maker->source_file, $pdf_path, "source_file: $pdf_path");
is ($map_maker->target_file_ext, 'png', 'png file extension');

my $refined_name = 'tandem-bike-riders';
is ($map_maker->refined_name, $refined_name, "refined_name: $refined_name");

my $base_dir = "$dest_dir/tandem-bike-riders";
is ($map_maker->base_dir, $base_dir, "base_dir: $base_dir");

my $rendered_dir = "$dest_dir/tandem-bike-riders/rendered";
is ($map_maker->rendered_dir, $rendered_dir, "rendered_dir: $rendered_dir");

my $descartes_dir = dirname (abs_path ($0));
is ($map_maker->descartes_dir, $descartes_dir, "descartes_dir: $descartes_dir");

my $share_dir = $map_maker->share_dir;
ok ($share_dir, "share_dir: $share_dir");

$map_maker->generate();

my $dir_h;
my @files;
opendir $dir_h, $rendered_dir;
@files = readdir $dir_h;
closedir $dir_h;
ok ( grep ( { $_ eq 'mini_map.png'  } @files ), 'mini_map.png');
ok ( grep ( { $_ eq 'thumbnail.png' } @files ), 'thumbnail.png');
ok ( grep ( { m{scale\d+[.]png$} } @files ) == 4, '4 scales');


foreach my $num (qw(100 150 200 300)) {
  ok (-d "$base_dir/scale$num", "$base_dir/scale$num");
  ok (-f "$base_dir/scale100/x0y0.png", "$base_dir/scale100/x0y0.png");
}

my $file;
$file = "$base_dir/scale100/x3y2.png";
ok (-f $file, $file);

$file = "$base_dir/scale150/x4y3.png";
ok (-f $file, $file);

$file = "$base_dir/scale200/x6y4.png";
ok (-f $file, $file);

$file = "$base_dir/scale300/x9y6.png";
ok (-f $file, $file);
