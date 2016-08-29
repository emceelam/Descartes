#!/usr/bin/perl

use warnings;
use strict;
use Test::More (tests => 1);
use Descartes::Lib qw(refine_file_name);

is (refine_file_name ("/tmp/space in file name.jpg"), "space_in_file_name",
   "refine_file_name()");