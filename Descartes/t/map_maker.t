#!/usr/bin/perl

use warnings;
use strict;

use Cwd qw(cwd abs_path);
use File::Basename qw(dirname);
use Test::More (tests => 8);

use Descartes::MapMaker;

my $dir = dirname(__FILE__);

my $map_maker = new Descartes::MapMaker(
  source_file => "$dir/skyline.jpg",
);

ok ($map_maker, "Descartes::MapMaker object");
is ($map_maker->dest_dir, '.', "dest_dir defaults to '.'");
is ($map_maker->source_file, "$dir/skyline.jpg", 'source_file');
is ($map_maker->target_file_ext, 'jpg', 'jpg file extension');
is ($map_maker->refined_name, 'skyline', 'refined_name');
is ($map_maker->base_dir, "$dir/skyline", 'base_dir');
is ($map_maker->rendered_dir, "$dir/skyline/rendered", 'rendered_dir');
is ($map_maker->descartes_dir, dirname (abs_path ($0)), 'descartes_dir');