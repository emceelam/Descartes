#!/usr/bin/perl -w

use AjaxMapMaker;

die "Usage: $0 filename1.pdf filename2.pdf etc.\n" if !@ARGV;
foreach my $pdf_name (@ARGV)
{
  die "That does not look like a pdf name, $pdf_name\n"
    if $pdf_name !~ /\.pdf$/;
  AjaxMapMaker->new($pdf_name)->generate();
}