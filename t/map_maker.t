#!/usr/bin/perl

use warnings;
use strict;

use Cwd qw(cwd abs_path);
use List::MoreUtils qw(any);
use File::Basename qw(dirname basename);
use File::Copy qw(copy);
use File::Path qw(rmtree);
use Descartes::MapMaker;
use Test::More (tests => 8);

my $t_dir       = dirname(__FILE__);
my $testimg_dir = "$t_dir/../testimg";
my $pdf_path    = "$testimg_dir/tandem-bike-riders.pdf",
my $dest_dir    = '/tmp';

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

