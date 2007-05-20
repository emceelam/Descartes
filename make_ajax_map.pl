#!/usr/bin/perl -w

use strict;
use AjaxMapMaker qw($mini_map_max_width $mini_map_max_height $mini_map_name);
use Getopt::Long qw(:config gnu_getopt auto_help);
use Pod::Usage;
use Image::Info qw(image_type image_info dim);
use Template;
use Data::Dumper;
use Cwd qw(cwd);
use Text::Wrap qw(wrap);

pod2usage (-verbose => 1) if !@ARGV;

my $f_quiet = 0;
my $f_skip_render = 0;
my @source_files;
my @directories;
my @non_existents;
my @problem_files;
my @rendered_files;
my %gen_parms;

GetOptions (
  'quiet' => \$f_quiet, 
  'scale:s' => \&scaling, 
  'skip_render' => \$f_skip_render,
  '<>' => \&process_graphic_file,
);

$gen_parms{f_quiet} = $f_quiet if $f_quiet;
$gen_parms{f_skip_render} = $f_skip_render if $f_skip_render;

SOURCE_FILE:
foreach my $source_file (@source_files) {
  print "Rendering $source_file\n";
  eval {
    AjaxMapMaker->new($source_file)->generate(%gen_parms);
  };
  if ($@) {
    push @problem_files, {file => $source_file, error => $@};
    next SOURCE_FILE;
  }
  push @rendered_files, $source_file;
}

foreach my $dir (@directories) {
  make_gallery($dir, %gen_parms);
}

if (@rendered_files) {
  print "Rendered files\n";
  print map {"  $_\n"} @rendered_files;
  print "\n";
}
if (@non_existents) {
  print "Non-existent files\n";
  print map {"  $_\n"} @non_existents;
  print "\n";
}
if (@problem_files) {
  print "Problem files\n";
  foreach my $problem (@problem_files) {
    print "  " . $problem->{file} . ":\n";
    print wrap ("    ", "    ", $problem->{error}) . "\n";
  }
  print "\n";
}

=head1 make_gallery
Take one directory full of graphic files. Call generate on each graphic file. 
Voila a gallery of google style maps.
=cut
sub make_gallery {
  my ($gallery_dir, @gen_parms) = @_;

  if (! opendir DIR, $gallery_dir)
  {
    push @problem_files, {
      file => $gallery_dir,
      error => "Could not open directory $gallery_dir\n",
    };
    return;
  }
  my @graphic_files = grep { m/jpeg|jpg|gif|png|pdf$/i } readdir DIR;
  closedir DIR;

  my @thumbs;
  GRAPHIC_FILE:
  foreach my $graphic_file (@graphic_files) {
    print "Rendering $gallery_dir/$graphic_file\n";
    my $map_maker =
      AjaxMapMaker->new("$gallery_dir/$graphic_file", $gallery_dir);
    my $image_dir = $map_maker->generate(@gen_parms);
    my $generated_dir = "$gallery_dir/$image_dir";

    my $mini_map_file = "$generated_dir/rendered/$mini_map_name";
    my $info = image_info ($mini_map_file);
    if (my $error = $info->{error}) {
       push @problem_files, {
         file => "$gallery_dir/$graphic_file",
         error => "Can't parse image info: $error",
       };
       next GRAPHIC_FILE;
    }
    push @rendered_files, "$gallery_dir/$graphic_file";
    my($mini_map_width, $mini_map_height) = dim($info);

    push @thumbs, {
      src => "$image_dir/rendered/$mini_map_name",
      full_view => "$image_dir/index.html",
      caption => $graphic_file,
      width => $mini_map_width,
      height => $mini_map_height,
    };
  }

  my $tt = Template->new ();
  $tt->process(
        'gallery_index.html.tt',
        {
          thumbs => \@thumbs,
        },
        "$gallery_dir/index.html"
  );
}

sub scaling {
  my ($option, $scale_string) = @_;

  die "Scales '$scale_string' are supposed to be numbers\n" 
    if $scale_string !~ /\d/;
  $gen_parms{scales} = [ split /[\s,]+/, $scale_string ];
}

sub process_graphic_file {
  my $source = shift;

  if (!-e $source) {
    push @non_existents, $source;
    return;
  }
  if (-d $source) {
    push @directories, $source;
    return;
  }

  if ($source !~ /\.pdf$/i) {
    my $type = image_type($source);
    if (my $error = $type->{error}) {
      push @problem_files, {
        file => $source,
        error => "Can not determine file type: $error" 
      };
      return;
    }

    if ($type->{file_type} !~ m/GIF|PNG|JPEG/) {
      push @problem_files, {
        file => $source,
        error => "Not pdf, png, gif or jpg",
      };
      return;
    }
  }

  push @source_files, $source;
}

__END__

=head1 SYNOPSIS

./make_ajax.pl filename1.pdf filename2.pdf etc.

=head1 DESCRIPTION

This program will take a graphics file (pdf, png, gif or jpg) and render the files
necessary to support a google style map.

=head1 ARGUMENTS

=head2 --scale

Sets the scale factors for the renders. For example, 75%, 100%, 125% and 150% is
represented as 

--scale=0.75,1,1.25,1.50

Please, no spaces.

=head2 --skip_render

Skip the image rendering stage. Only do this if you know you have already 
rendered the images. (Feature is dysfunctional.)

=head2 --help

Print this help section

=head2 --quiet value

Currently unimplemented

=cut

