package AjaxMapMaker;

# Written by Lambert Lum (emceelam@warpmail.net)

=head1 NAME

AjaxMapMaker

=head1 SYNOPSIS

AjaxMapMaker->new(source_file, dest_dir)->generate();

source_file is a pdf, jpg, png, gif, or tiff.
dest_dir is optional, defaults to '.'.

=cut
use version; our $VERSION = qv('0.1');  # Must all be on same line
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK
  = qw ( $mini_map_max_width $mini_map_max_height $mini_map_name $tile_size);

use strict;
use Imager;
use Image::Info qw(image_info dim);
use Template;
use Readonly;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Find qw(find);
use File::Copy qw(move copy);
use File::Path qw(mkpath rmtree);
use Params::Validate qw(validate ARRAYREF BOOLEAN);
use Math::Round qw(round);
use Cwd;
use List::MoreUtils qw(firstval);
use Carp qw(croak);
use Storable qw(store retrieve);
use Data::Dumper;

Readonly our $tile_size => 256;
Readonly our $mini_map_max_width  => 200;
Readonly our $mini_map_max_height => 200;
Readonly our $mini_map_name => "mini_map.png";

sub new {
  my ($class_name, $source_file, $dest_dir, $catalog_file) = @_;

  my ($base_name, $file_ext) = $source_file =~ m{(?:.*/)?(.*)\.([^.]+)$};
  $base_name =~ s/[^a-zA-Z0-9.\-]/_/g;
  $file_ext = lc $file_ext;
  $dest_dir ||= '.';
  $dest_dir =~ s|/$||;
  my $dest_base = "$dest_dir/$base_name";
  my $tiles_subdir = "tiles";
  my $start_dir = "$dest_dir/__processing";
  my $base_dir = "$start_dir/$base_name";
  my $f_pdf = $file_ext eq 'pdf';
  my $self = {
    source_file_name => $source_file,
    source_file_ext  => $file_ext,
    dest_dir => $dest_dir,
    dest_base => $dest_base,
    start_dir => $start_dir,
    base_dir => $base_dir,
    base_name => $base_name,
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

  # catalog_file
  $catalog_file ||= "catalog.dat";
  my $catalog;
  if (-e $catalog_file) {
    $catalog = retrieve($catalog_file) 
      || croak "can not retrieve $catalog_file";
  }
  $self->{catalog_file} = $catalog_file;

  # catalog_item
  my $catalog_item = firstval {$_->{dir} eq $base_name} @$catalog;
  if (!$catalog_item) {
    $catalog_item = {
      file => "$base_name.$file_ext",
      dir  => $base_name,
    };
    push @$catalog, $catalog_item;   # $catalog autovivifies
  }
  $self->{catalog_item} = $catalog_item;
  $self->{catalog} = $catalog;

  return bless $self, $class_name;
}

sub DESTROY {
  my $self = shift;
  store $self->{catalog}, $self->{catalog_file};
  print "Now Storing catalog\n";
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

  # render at different resolutions
  # at scale 100%, monitor resolution is 72dpi
  foreach my $scale (@$scales) {
    my $dpi = round($scale * 72);
    system ("nice gs -q -dSAFER -dBATCH -dNOPAUSE " .
              "-sDEVICE=png16m -dUseCropBox -dMaxBitmap=300000000 " .
              "-dFirstPage=1 -dLastPage=1 -r$dpi " .
              "-dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dDOINTERPOLATE " .
              "-sOutputFile=$rendered_dir/$base_name.png $pdf_name");
    $info = image_info ("$rendered_dir/$base_name.png");
    if ($error = $info->{error}) {
      die "Can't parse image info: $error";
    }
    my ($width, $height) = dim ($info);
    my $percent_scale = sprintf "%03d", $scale * 100;
    my $dest_file_name =
      "w${width}_h${height}_scale${percent_scale}.png";
    rename "$rendered_dir/$base_name.png", "$rendered_dir/$dest_file_name";
    print "rendered $dest_file_name\n";
    push @scale_and_files, [ $scale, $dest_file_name ];
  }
  $self->{catalog_item}{scales} = $scales;

  return \@scale_and_files;
}

sub create_mini_map {
  my ($self, $file_name) = @_;
  my $rendered_dir = $self->{rendered_dir};
  my $img = Imager->new();
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr . "\n";
  my $scaled_img = $img->scale (
                     xpixels => $mini_map_max_width, 
                     ypixels => $mini_map_max_height,
                     type=>'min');
  $scaled_img->write (file => "$rendered_dir/$mini_map_name")
    || die "Could not write mini map: " . $img->errstr . "\n"
}

sub tile_image {
  my ($self, $scale, $file_name)  = @_;

  my $rendered_dir = $self->{rendered_dir};
  my $base_dir = $self->{base_dir};
  my $base_name = $self->{base_name};
  my $file_ext = $self->{target_file_ext};
  my ($img_width, $img_height) =
    $file_name =~ m/w(\d+)_h(\d+)_scale(?:\d+)\.(?:png|gif|jpg)$/;
  print "$base_name, $img_width, $img_height\n";
  my $img = Imager->new;
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr;

  my $tile_cnt = 0;
  my $max_y = $img_height / $tile_size;
  my $max_x = $img_width  / $tile_size;
  for   (my $y=0; $y < $max_y; $y++) {
    my $scale_dir = "$base_dir/scale" . ($scale * 100);
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
  my ($mini_map_width, $mini_map_height) = dim($info);

  my $tt = Template->new ();
  $tt->process(
        'index.html.tt',
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
  my $start_dir = $self->{start_dir};

  chdir("$cwd/$start_dir") || die "zip_files could not chdir\n";
  die "At ". cwd(). ", where is directory $base_dir?"
    if !-d $base_dir;

  find ( {
    wanted => sub { $File::Find::dir !~ m/rendered$/ &&
                      $zip->addFileOrDirectory($_) },
    no_chdir => 1
  }, $base_dir);
  $zip->addFile("$base_dir/rendered/mini_map.png");
  unless ($zip->writeToFileNamed("$base_name.zip") == AZ_OK) {
    die "$base_name.zip write error";
  }
  move "$base_name.zip", $base_dir ||
   die "At ". cwd() . ", Could not move zip file: $!";

  chdir $cwd;
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

  my $img = Imager->new;
  $img->read (file => $source_file)
    || croak "scale_raster_image:" . $img->errstr() . "\n";

  foreach $scale (@$scales) {
    my $scaled_img = $img->scale(scalefactor => $scale);
    ($width, $height) = ($scaled_img->getwidth(), $scaled_img->getheight());
    $dest_file_name = "w${width}_h${height}_scale"
      . sprintf ("%03d", $scale * 100) . ".$file_ext";

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
  $self->{catalog_item}{scales} = $scales;

  return \@scale_and_files;
}

sub move_generated_files_to_final_directory {
  my $self = shift;

  my $dest   = cwd() . '/' . $self->{dest_base};
  my $source = cwd() . '/' . $self->{base_dir};

  rmtree $dest;
  move $source, $dest;
}

=head2 generate

When called, generate will coordinate the creation of the files neccessary
to create an AJAX map

=head3 parameters

scales: List ref of scaling factors. 100% scale factor is 1. 50% is 0.5.
So on and so on

=head3 return

returns the directory where generated files reside

=cut
sub generate {
  my $self = shift;
  my @file_names;
  my $scale_and_files;
  my %p = validate ( @_, {
    scales => { type => ARRAYREF, optional => 1 },
    f_quiet => { type => BOOLEAN, default => 0 },
    f_skip_render => { type => BOOLEAN, default => 0 },
  } );

  # scale settings
  my $scales = $p{scales};
  if (!$scales) {
    $scales = $self->{f_pdf} ? [1, 1.5, 2, 3] : [0.25, 0.5, 0.75, 1];
  }
  $self->{scales} = $scales;

  mkpath ( [
    $self->{base_dir},
    $self->{rendered_dir},
    map { $self->{base_dir} . '/scale' . ($_ * 100) } @$scales,
  ] );
  if (!$p{f_skip_render})
  {
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
    $self->create_mini_map ($file_names[-1]);
      # Create a mini map based on the last file. Last is typically largest.
  }

  $self->generate_html (@file_names);
  $self->zip_files ();
  $self->move_generated_files_to_final_directory();

  # return the image directory where generated files are located
  return $self->{base_name};
}

1;