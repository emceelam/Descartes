#!/usr/bin/perl -w

use strict;
use AjaxMapMaker;
use Getopt::Long qw(:config gnu_getopt auto_help);
use Pod::Usage;
use Image::Info qw(image_type image_info dim);
use Template;
use Readonly;
use Data::Dumper;
use Cwd qw(cwd);

# Copied from AjaxMapMaker.pm
Readonly my $mini_map_max_width  => 200;
Readonly my $mini_map_max_height => 200;
Readonly my $mini_map_name => "mini_map.png";

pod2usage (-verbose => 1) if !@ARGV;

my $f_quiet = 0;
my $f_skip_render = 0;
my $help;
my @source_files;
my @directories;
my %gen_parms;

GetOptions (
  'quiet' => \$f_quiet, 
  'scale:s' => \&scaling, 
  'skip_render' => \$f_skip_render,
  '<>' => \&process_graphic_file,
);

$gen_parms{f_quiet} = $f_quiet if $f_quiet;
$gen_parms{f_skip_render} = $f_skip_render if $f_skip_render;

foreach my $source_file (@source_files) {
  AjaxMapMaker->new($source_file)->generate(%gen_parms);
}

foreach my $dir (@directories) {
  make_gallery($dir, %gen_parms);
}

=head1 make_gallery
Take one directory full of graphic files. Call generate on each graphic file. 
Voila a gallery of google style maps.
=cut
sub make_gallery {
  my ($gallery_dir, @gen_parms) = @_;

  opendir DIR, $gallery_dir || die "Could not open $gallery_dir\n";
  my @graphic_files = grep { m/jpeg|jpg|gif|png|pdf$/i } readdir DIR;
  closedir DIR;

  my %thumb;
  my @thumbs;

  my @gallery_thumbnails;
  foreach my $graphic_file (@graphic_files) {
    my $map_maker =
      AjaxMapMaker->new("$gallery_dir/$graphic_file", $gallery_dir);
    my $image_dir = $map_maker->generate(@gen_parms);
    my $generated_dir = "$gallery_dir/$image_dir";

    my $mini_map_file = "$generated_dir/rendered/$mini_map_name";
    my $info = image_info ($mini_map_file);
    if (my $error = $info->{error}) {
       die "Can't parse image info: $error";
    }
    my($mini_map_width, $mini_map_height) = dim($info);

    push @thumbs, {
      $generated_dir => {
        src => "$image_dir/rendered/$mini_map_name",
        full_view => "$image_dir/index.html",
        caption => $graphic_file,
        width => $mini_map_width,
        height => $mini_map_height,
      }
    };
    $thumb{$generated_dir} = {
      src => $mini_map_file,
      full_view => "$generated_dir/index.html",
      caption => $graphic_file,
      width => $mini_map_width,
      height => $mini_map_height,
    };
  }

  my @row;
  my @thumb_rows;
  while (@thumbs)
  {
    @row = splice (@thumbs, 0, 3);
    push @thumb_rows, [@row]; 
  }

  my $tt = Template->new ();
  $tt->process(
        'gallery_index.html.tt',
        {
          thumb_rows => \@thumb_rows,
        },
        "$gallery_dir/index.html"
  );
}

sub scaling {
  my ($option, $scale_string) = @_;

  die "Scales '$scale_string' are supposed to be numbers\n" 
    if $scale_string !~ /\d|\s|\./;
  $gen_parms{scales} = [ split /\s/, $scale_string ];
}

sub process_graphic_file {
  my $source = shift;

  if (-d $source)
  {
    push @directories, $source;
    return;
  }

  if ($source !~ /\.pdf$/i) {
    my $type = image_type($source);
    if (my $error = $type->{error}) {
      die "Can't determine file type for $source: $error\n";
    }

    die "That does not look like a pdf, png, gif or jpg file, $source\n"
      if $type->{file_type} !~ m/GIF|PNG|JPEG/;
  }
  push @source_files, $source;
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

=head2 --skip_render

Skip the image rendering stage. Only do this if you know you have already 
rendered the images. (Feature is unimplemented.)

=head2 --help

Print this help section

=head2 --quiet value

Currently unimplemented

=cut

