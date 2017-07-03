#!/usr/bin/env perl

use warnings;
use strict;
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(rmtree);
use List::MoreUtils qw(any);
use Test::More tests => 27;

my $t_dir       = dirname(__FILE__);
my $bin_dir     = "$t_dir/../bin";
my $testimg_dir = "$t_dir/../testimg";
my $basename    = basename($0);
my $gallery_dir = "/tmp/$basename";
ok (!-d $gallery_dir, "Clean slate: no pre-existing $gallery_dir");
mkdir $gallery_dir;
ok (-d $gallery_dir, "mkdir $gallery_dir");
foreach my $test_img (qw(tandem-bike-riders.pdf teaparty.pdf)) {
  my $source = "$testimg_dir/$test_img";
  my $dest = "$gallery_dir/$test_img";
  ok (-f $source, "source: $source");
  copy ($source, $dest);
  ok (-f $dest, "dest: $dest");
}
my $cmd;
$cmd = "perl $bin_dir/make_slippy_map.pl --scale='1' $gallery_dir >/dev/null 2>&1";
system $cmd;

ok (opendir(my $dir_handle, $gallery_dir), "open $gallery_dir directory");
my @all_files = readdir($dir_handle);
ok (closedir($dir_handle), "closed $gallery_dir directory");;

my @graphic_files = grep { m/pdf|png|gif|jpg/i } @all_files;
ok (@graphic_files, "graphic files in $gallery_dir");

foreach my $graphic_file (@graphic_files)
{
  $graphic_file =~ s/\.(.*?)$//;
  $graphic_file =~ s/[^a-zA-Z0-9.\-]/_/g;
  ok (-d "$gallery_dir/$graphic_file", "$gallery_dir/$graphic_file directory exist");

  # Renders
  ok (opendir (my $rendered_dir_handle, "$gallery_dir/$graphic_file/rendered"),
    "opened $gallery_dir/$graphic_file/rendered");
  my @renders = readdir ($rendered_dir_handle);
  ok (closedir ($rendered_dir_handle),
    "closed $gallery_dir/$graphic_file/rendered");
  ok (-f "$gallery_dir/$graphic_file/rendered/mini_map.png",
    "$graphic_file/rendered/mini_map.png exists");
  my @scaled_images = grep { m/^w\d+_h\d+_scale\d+/ } @renders;
  @scaled_images =
    sort {
      my ($a_scale) = $a =~ /scale(\d+)/;
      my ($b_scale) = $b =~ /scale(\d+)/;
      $a_scale <=> $b_scale
      } @scaled_images;
  note (map {"$_\n"} @scaled_images);
  ok (@scaled_images, "At least one render");

  # Scales
  my $scale_dir = "$gallery_dir/$graphic_file/scale100";
  ok (opendir (my $scales_dir_handle, $scale_dir),
      "opened $scale_dir");
  my @tiles = readdir ($scales_dir_handle);
  ok (closedir ($scales_dir_handle), "closed $scale_dir");
  note (scalar(@tiles) . " tiles found\n");
  ok ( (any { m/^x0y0\./ } @tiles), "x0y0 tile exist" );
}

ok (-f "$gallery_dir/index.html",
  "$gallery_dir/index.html exist");

rmtree ($gallery_dir);
ok (!-e $gallery_dir, "remove at end of test, $gallery_dir");

