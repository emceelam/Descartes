#!/usr/bin/perl -w

use strict;
use AjaxMapMaker;
use Getopt::Long qw(:config gnu_getopt auto_help);
use Pod::Usage;
use Image::Info qw(image_type);

pod2usage (-verbose => 1) if !@ARGV;

my $f_quiet = 0;
my $help;
my @source_files;
my @gen_parms;

GetOptions (
  'quiet' => \$f_quiet, 
  'scale:s' => \&scaling, 
  '<>' => \&process_graphic_file,
);

foreach my $source_file (@source_files) {
  AjaxMapMaker->new($source_file)->generate(@gen_parms);
}

sub scaling {
  my ($option, $scale_string) = @_;

  die "Scales '$scale_string' are supposed to be numbers\n" 
    if $scale_string !~ /\d|\s|\./;
  push @gen_parms, (scales => [ split /\s/, $scale_string ]);
}

sub process_graphic_file {
  my $source_file = shift;

  if ($source_file !~ /\.pdf$/i) {
    my $type = image_type($source_file);
    if (my $error = $type->{error}) {
      die "Can't determine file type for $source_file: $error\n";
    }

    die "That does not look like a pdf, png, gif or jpg file, $source_file\n"
      if $type->{file_type} !~ m/GIF|PNG|JPEG/;
  }
  push @source_files, $source_file;
}

__END__

=head1 SYNOPSIS

$0 filename1.pdf filename2.pdf etc.

=head1 DESCRIPTION

This program will take a graphics file (pdf, png, gif or jpg) and render the files
necessary to support a google style map.

=head1 ARGUMENTS

=head2 --scale

Sets the scale factors for the renders. For example, 75%, 100%, 125% and 150% is
represented as 

--scale='0.75 1 1.25 1.50'

=head2 --help

Print this help section

=head2 --quiet value

Currently unimplemented

=cut

