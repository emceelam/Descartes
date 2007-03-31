#!/usr/bin/perl -w

use strict;
use Test::More qw (no_plan);
use List::MoreUtils qw(any);

system q { perl make_ajax_map.pl --scale="1" gallery_test };

my $gallery_dir = "gallery_test";
ok (opendir(DIR, $gallery_dir), "open $gallery_dir directory");
my @all_files = readdir(DIR);
ok (closedir(DIR), "closed $gallery_dir directory");;

my @graphic_files = grep { m/pdf|png|gif|jpg/i } @all_files;
ok (@graphic_files, "QA tester needs graphic files in $gallery_dir");

foreach my $graphic_file (@graphic_files)
{
  $graphic_file =~ s/\.(.*?)$//;
  $graphic_file =~ s/[^a-zA-Z0-9.\-]/_/g;
  ok (-d "$gallery_dir/$graphic_file", "$graphic_file directory exist");

  # Renders
  ok (-M "$gallery_dir/$graphic_file" < 0, 
    "Built $graphic_file directory during this script's run");
  ok (opendir (RENDERED_DIR, "$gallery_dir/$graphic_file/rendered"),
    "opened $gallery_dir/$graphic_file/rendered");
  my @renders = readdir (RENDERED_DIR);
  ok (closedir (RENDERED_DIR),
    "closed $gallery_dir/$graphic_file/rendered");
  ok (-f "$gallery_dir/$graphic_file/rendered/mini_map.png",
    "$graphic_file/rendered/mini_map.png exist");
  my @scaled_images = grep { m/^w\d+_h\d+_scale\d+/ } @renders;
  @scaled_images =
    sort {
      my ($a_scale) = $a =~ /scale(\d+)/;
      my ($b_scale) = $b =~ /scale(\d+)/;
      $a_scale <=> $b_scale
      } @scaled_images;
  print map {"$_\n"} @scaled_images;

  # Tiles
  ok (opendir (TILES_DIR, "$gallery_dir/$graphic_file/tiles"),
    "opened $graphic_file/tiles directory");
  my @tiles = readdir (TILES_DIR);
  ok (closedir (TILES_DIR),
    "closed $graphic_file/tiles directory");

  print scalar(@tiles) . " tiles found\n";
  ok ( (any { m/^x0y0z0\./ } @tiles), "x0y0z0 tile exist" );
}

ok (-d "$gallery_dir/__processing", 
  "$gallery_dir/__processing directory exist");
ok (-f "$gallery_dir/index.html",
  "$gallery_dir/index.html exist");
ok (-M "$gallery_dir/index.html" < 0,
  "$gallery_dir/index.html generated recently");