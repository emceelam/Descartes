#!/usr/bin/perl -w

use AjaxMapMaker;

die "Usage: $0 filename1.pdf filename2.pdf etc.\n" if !@ARGV;
foreach my $source_file (@ARGV)
{
  die "That does not look like a pdf, png or jpg file, $source_file\n"
    if $source_file !~ /\.(pdf|png|jpg)$/i;
  AjaxMapMaker->new($source_file)->generate();
}