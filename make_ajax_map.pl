#!/usr/bin/perl -w

use AjaxMapMaker;

die "Usage: $0 filename.pdf\n" if !@ARGV;

AjaxMapMaker->new($ARGV[0])->generate;

