package Descartes::AjaxMapMaker;

use version; our $VERSION = qv('0.1');  # Must all be on same line
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw ( $mini_map_max_width $mini_map_max_height $mini_map_name
                  $tile_size);

use strict;
use Imager;
use Image::Info qw(image_info dim);
use Template;
use Readonly;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Find qw(find);
use File::Copy qw(move copy);
use File::Path qw(mkpath rmtree);
use Params::Validate qw(validate ARRAYREF BOOLEAN SCALAR);
use Math::Round qw(round);
use Cwd qw(cwd abs_path);
use List::MoreUtils qw(firstval);
use Carp qw(croak);
use Storable qw(store retrieve);
use File::Touch qw(touch);
use File::Basename qw(dirname);
use Data::Dumper;

Readonly our $tile_size => 256;
Readonly our $mini_map_max_width  => 200;
Readonly our $mini_map_max_height => 200;
Readonly our $mini_map_name => "mini_map.png";
Readonly our $thumbnail_max_width  => 100;
Readonly our $thumbnail_max_height => 100;
Readonly our $thumbnail_name       => "thumbnail.png";
Readonly our $low_res_max_width    => 640;
Readonly our $low_res_max_height   => 480;

sub new {
  my ($class_name, $source_file, $dest_dir, $html_template) = @_;

  my ($base_name, $file_ext) = $source_file =~ m{(?:.*/)?(.*)\.([^.]+)$};
  $base_name =~ s/[^a-zA-Z0-9.\-]/_/g;
  $file_ext = lc $file_ext;
  $dest_dir ||= '.';
  $dest_dir =~ s|/$||;
  my $dest_base = "$dest_dir/$base_name";
  my $tiles_subdir = "tiles";
  my $base_dir = "$dest_dir/$base_name";
  my $f_pdf = $file_ext eq 'pdf';
  my $self = {
    descartes_dir => dirname (abs_path ($0)),
    source_file_name => $source_file,
    source_file_ext  => $file_ext,
    dest_dir => $dest_dir,
    dest_base => $dest_base,
    base_dir => $base_dir,
    base_name => $base_name,
    html_template => ($html_template || 'index.html.tt'),
    rendered_dir => "$base_dir/rendered",
    tiles_dir => "$base_dir/$tiles_subdir",
    tiles_subdir => $tiles_subdir,
    f_pdf => $f_pdf,
  };

  # target_file_ext
  my %sourceFileExt_to_targetFileExt = (
    pdf  => 'png',
    tif  => 'png',
    tiff => 'png',
    gif  => 'gif',
    jpg  => 'jpg',
    jpeg => 'jpg',
    png  => 'png',
  );
  $self->{target_file_ext} = $sourceFileExt_to_targetFileExt{ $file_ext };

  return bless $self, $class_name;
}

# Render the current pdf into multiple scales and
# return the scales and file names.
#   [ [ scale1, filename1 ],
#     [ scale2, filename2 ],
#     ... ]
sub pdf_to_png {
  my $self = shift;
  my $base_dir = $self->{base_dir};
  my $base_name = $self->{base_name};
  my $rendered_dir = $self->{rendered_dir};
  my $pdf_name = $self->{source_file_name};
  my $scales = $self->{scales};
  my $error;
  my $info;
  my @scale_and_files;
  $self->{target_file_ext} = 'png';
  my @renders;
  my $scale;
  my %seen;

  my $render_and_files = get_previous_scale_renders($pdf_name, $rendered_dir);
  @renders = map { $_->[0] } @$render_and_files;
  @seen{@renders} = ();
  my @unrendered_scales = grep { !exists $seen{$_} } @$scales;

  # render at different resolutions
  # at scale 100%, monitor resolution is 72dpi
  foreach $scale (@unrendered_scales) {
    my $dpi = round($scale * 72);
    my $output_name = "$rendered_dir/$base_name.png";

    system ("nice gs -q -dSAFER -dBATCH -dNOPAUSE " .
              "-sDEVICE=png16m -dUseCropBox -dMaxBitmap=300000000 " .
              "-dFirstPage=1 -dLastPage=1 -r$dpi " .
              "-dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dDOINTERPOLATE " .
              "-sOutputFile=$output_name $pdf_name");

    $info = image_info ($output_name);
    croak "Can't parse image info for $output_name: $error"
      if ($error = $info->{error});
    my ($width, $height) = dim ($info);
    my $percent_scale = $scale * 100;
    my $dest_file_name =
      "w${width}_h${height}_scale${percent_scale}.png";
    rename "$rendered_dir/$base_name.png", "$rendered_dir/$dest_file_name";
    print "rendered $dest_file_name\n";
    push @scale_and_files, [ $scale, $dest_file_name ];
  }
  $self->{catalog_item}{scales} = $scales;

  return [sort { $a->[0] <=> $b->[0] } (@$render_and_files, @scale_and_files)];
}

# You should consolidate this function and create_low_res() into an object
# so that you don't have to re-load the source image each time. Way too
# time consuming.
sub create_scaled_down_image {
  my $self = shift;
  my %p = validate ( @_, {
    source     => { type => SCALAR },
    target     => { type => SCALAR },
    max_width  => { type => SCALAR },
    max_height => { type => SCALAR },
  } );

  my $file_name = $p{source};
  my $target = $p{target};
  my $rendered_dir = $self->{rendered_dir};

  return if is_up_to_date(
                  source => "$rendered_dir/$file_name",
                  target => "$rendered_dir/$target",
                );

  print "Create $target based on $file_name\n";
  my $img = Imager->new();
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr . "\n";
  my $scaled_img = $img->scale (
                     xpixels => $p{max_width}, 
                     ypixels => $p{max_height},
                     type=>'min');
  $scaled_img->write (file => "$rendered_dir/$target")
    || die "Could not write $rendered_dir/$target: " . $img->errstr . "\n";
}

sub create_hi_res {
  my ($self, $file_name) = @_;
  my $rendered_dir = $self->{rendered_dir};
  link $file_name, "$rendered_dir/hi_res" ||
    croak "could not link";
}

sub create_low_res {
  my ($self, $file_name) = @_;
  my $rendered_dir = $self->{rendered_dir};
  my $low_res_name = "low_res." . $self->{target_file_ext};

  return if is_up_to_date(
                  source => "$rendered_dir/$file_name",
                  target => "$rendered_dir/$low_res_name",
                );

  print "Rendering $rendered_dir/$low_res_name\n";
  my $img = Imager->new();
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr . "\n";
  my $scaled_img = $img->scale (
                     xpixels => 640,
                     ypixels => 480,
                     type=>'min');
  $scaled_img->write (file => "$rendered_dir/$low_res_name")
    || die "Could not write low res: " . $img->errstr . "\n";
}

sub tile_image {
  my ($self, $scale, $file_name)  = @_;

  my $rendered_dir = $self->{rendered_dir};
  my $base_dir = $self->{base_dir};
  my $scale_dir = "$base_dir/scale" . ($scale * 100);

  if (is_up_to_date (
        source => "$rendered_dir/$file_name", target => $scale_dir)) {
    print "Already rendered $scale_dir\n";
    return;
  }
  mkpath ($scale_dir,1);

  # More variable initialization
  my $base_name = $self->{base_name};
  my $file_ext = $self->{target_file_ext};
  my ($img_width, $img_height) =
    $file_name =~ m/w(\d+)_h(\d+)_scale(?:\d+)\.(?:png|gif|jpg)$/;
  print "$base_name, $img_width, $img_height\n";
  my $img = Imager->new;
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr;

  # Make the tiles
  my $tile_cnt = 0;
  my $max_y = $img_height / $tile_size;
  my $max_x = $img_width  / $tile_size;
  for   (my $y=0; $y < $max_y; $y++) {
    for (my $x=0; $x < $max_x;  $x++) {
      my $tile_img = $img->crop (
                       left => $x * $tile_size, top => $y * $tile_size,
                       width=> $tile_size, height => $tile_size);
      my $tile_name =
        "$scale_dir/x$x" . "y$y" . ".$file_ext";
      $tile_img->write (file => $tile_name)
        || die "Cannot write tile $tile_name: ". $tile_img->errstr();
      $tile_cnt++;
    }
    print "Finished row $y. Tiles written so far: $tile_cnt\n"
      if ($y & 0x1) == 0;   # even rows only
  }
  touch($scale_dir);
  print "Total tiles written: $tile_cnt\n";
}

sub generate_html {
  my ($self, @file_names) = @_;
  my $rendered_dir = $self->{rendered_dir};
  my $base_dir = $self->{base_dir};
  my $error;
  my @dimensions;
  my $info;

  foreach my $file_name (@file_names) {
    my ($width, $height, $scale) =
      $file_name =~ m/w(\d+)_h(\d+)_scale[0]*(\d+)\.(?:jpg|png|gif)$/;
    push @dimensions, { width => $width, height => $height, scale => $scale };
  }
  $info = image_info("$rendered_dir/$mini_map_name");
  croak ("image_info failed: " . $info->{error}) 
    if $info->{error};
  my ($mini_map_width, $mini_map_height) = dim($info);

  my $tt = Template->new (INCLUDE_PATH => $self->{descartes_dir});
  $tt->process(
        $self->{html_template},
        {
          file_base => $self->{base_name},
          tiles_subdir => $self->{tiles_subdir},
          tile_size => $tile_size,
          tile_file_ext => $self->{target_file_ext},
          dimensions => \@dimensions,
          view_port_width  => 500,
          view_port_height => 400,
          mini_map_width  => $mini_map_width,
          mini_map_height => $mini_map_height,
        },
        "$base_dir/index.html"
  ) || die $tt->error(), "\n";
}

sub zip_files {
  my ($self) = @_;
  my $dest_dir = $self->{dest_dir};
  my $base_name = $self->{base_name};
  my $base_dir = $base_name;
  my $zip = Archive::Zip->new();
  my $cwd = cwd();

  print "creating zip archive\n";
  chdir($dest_dir) || die "zip_files() could not chdir\n";
  die "At ". cwd(). ", where is directory $base_dir?"
    if !-d $base_dir;
  unlink "$base_dir/$base_name.zip";

  find (
    {
      wanted => sub { $File::Find::dir !~ m/rendered$/ &&
                        $zip->updateMember($_, $_) },
      no_chdir => 1
    },
    $base_dir
  );
  $zip->addFile("$base_dir/rendered/mini_map.png");
  unless ($zip->writeToFileNamed("$base_dir/$base_name.zip") == AZ_OK) {
    croak "$base_name.zip write error";
  }

  chdir $cwd;  # back to the original directory
}

# scale a raster image, save the scaled images
# and return the scales and file names.
#   [ [ scale1, filename1 ],
#     [ scale2, filename2 ],
#     ... ]
sub scale_raster_image {
  my $self = shift;
  my $scales = $self->{scales};
  my $source_file = $self->{source_file_name};
  my $rendered_dir = $self->{rendered_dir};
  my $base_name = $self->{base_name};
  my $file_ext = $self->{target_file_ext};
  my ($width, $height);
  my $scale;
  my @scale_and_files;
  my $dest_file_name;

  my $render_and_files
        = get_previous_scale_renders ($source_file, $rendered_dir);
  my %seen;
  my @renders = map {$_->[0]} @$render_and_files;
  @seen{@renders} = ();
  my @unrendered_scales = grep { !exists $seen{$_} } @$scales;

  my $img;
  if (@unrendered_scales) {
    $img = Imager->new;
    $img->read (file => $source_file)
      || croak "scale_raster_image: source_file => $source_file, " .
           $img->errstr() . "\n";
  }

  foreach $scale (@unrendered_scales) {
    my $scaled_img = $img->scale(scalefactor => $scale);
    ($width, $height) = ($scaled_img->getwidth(), $scaled_img->getheight());
    $dest_file_name = "w${width}_h${height}_scale"
      . $scale * 100 . ".$file_ext";

    if ($scale == 1) {
      print "Copied $dest_file_name\n";
      copy $source_file, "$rendered_dir/$dest_file_name"
        || die "unable to write $dest_file_name\n";
    }
    else {
      print "Rendered $dest_file_name\n";
      $scaled_img->write (file => "$rendered_dir/$dest_file_name")
        or die $scaled_img->errstr;
    }
    push @scale_and_files, [$scale, $dest_file_name];
  }

  return [sort {$a->[0] <=> $b->[0]} (@$render_and_files, @scale_and_files) ];
}

sub generate {
  my $self = shift;
  my @file_names;
  my $scale_and_files;
  my %p = validate ( @_, {
    scales   => { type => ARRAYREF, optional => 1 },
    f_quiet  => { type => BOOLEAN,  default  => 0 },
    f_zip    => { type => BOOLEAN,  default  => 1 },
  } );

  # scale settings
  my $scales = $p{scales};
  if (!$scales) {
    $scales = $self->{f_pdf} ? [1, 1.5, 2, 3] : [0.25, 0.5, 0.75, 1];
  }
  $self->{scales} = $scales;

  mkpath ($self->{rendered_dir}, 1);
  if ($self->{f_pdf}) {
    $scale_and_files = $self->pdf_to_png ();
  }
  else {
    $scale_and_files = $self->scale_raster_image ();
  }
  @file_names = map { $_->[1] } @$scale_and_files;
  foreach my $row (@$scale_and_files) {
    my ($scale, $file_name) = @$row;
    $self->tile_image ($scale, $file_name);
  }
  my $source = $file_names[-1];
  # Create scaled down images based on the last file. Last is typically largest.
  $self->create_scaled_down_image (
    target => $mini_map_name, source => $source,
    max_width => $mini_map_max_width, max_height => $mini_map_max_height);
  $self->create_scaled_down_image (
    target => $thumbnail_name, source => $source,
    max_width => $thumbnail_max_width, max_height => $thumbnail_max_height);
  $self->create_scaled_down_image (
    target => "300x300.png", source => $source,
    max_width => 300, max_height => 300);
  $self->create_hi_res  ($file_names[-1]);
  $self->create_low_res ($file_names[-1]);

  $self->generate_html (@file_names);
  if ($p{f_zip}) {
    $self->zip_files ();    # slow
  }

  # return the image directory where generated files are located
  return $self->{base_name};
}

sub is_up_to_date {
  # named parameters are only present to make the code clearer to read
  # when calling this function.
  my %p = validate (@_, {
    source => {type => SCALAR},
    target => {type => SCALAR},
  });

  # Check modification times
  # Has target been generated more recently than source
  return (stat $p{target})[9] > (stat $p{source})[9]
    if (-e $p{target});

  return 0;
}

sub get_previous_scale_renders {
  my ($source, $rendered_dir) = @_;
  my @render_and_files;

  opendir (my $dir_handle, $rendered_dir) 
    || croak "Could not open $rendered_dir";
  @render_and_files
      = map  { my ($scale) = /scale(\d+)[.][a-z]{3}$/;
               [ $scale/100 , $_ ] }
        grep { is_up_to_date (source=> $source, target=> "$rendered_dir/$_") }
        grep { /scale\d+[.][a-z]{3}$/ }
        readdir $dir_handle;
  closedir ($dir_handle);
  return \@render_and_files;
}

sub get_base_name {
  my $self = shift;
  return $self->{base_name};
}

# Currently not used, but will be
sub get_scale_render {
  my ($source, $rendered_dir) = @_;

  opendir (my $dir_handle, $rendered_dir)
    || croak "Could not open $rendered_dir";
  my %scale_render
      = map  { my ($scale) = /scale(\d+)[.]png$/;
               $scale/100 , $_ }
        grep { is_up_to_date (source=> $source, target=> "$rendered_dir/$_") }
        grep { /scale\d+[.]png$/ }
        readdir $dir_handle;
  closedir ($dir_handle);

  return \%scale_render;
}

1;

__END__

=head1 NAME

AjaxMapMaker - Makes AJAX maps

=head1 SYNOPSIS

AjaxMapMaker->new(source_file, dest_dir)->generate();

source_file is a pdf, jpg, png, gif, or tiff.
dest_dir is optional, defaults to current directory.

=head1 DESCRIPTION

This class generates an AJAX map if given a pdf, jpg, png, gif or tiff file.
The files are deposited in a subdirectory whose name is take from the file name sans file extension, e.g. The funkyfile.pdf AJAX map is rendered in 'funkyfile' subdirectory.

=head1 METHODS

=head2 generate

When called, generate will coordinate the creation of the files neccessary
to create an AJAX map

=head3 parameters

scales: List ref of scaling factors. 100% scale factor is 1. 50% is 0.5.
So on and so on

f_zip: By default, zip file of generated files is always created.

=head3 return

returns the directory where generated files reside

=cut

=head1 AUTHOR

Written by Lambert Lum (emceelam@warpmail.net)

