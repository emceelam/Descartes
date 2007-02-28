package AjaxMapMaker;

# Written by Lambert Lum (emceelam@warpmail.net)

use strict;
use Imager;
use Image::Info qw(image_info dim);
use Template;
use Readonly;
#use Data::Dumper;

Readonly my $tile_width  => 100;
Readonly my $tile_height => 100;
Readonly my $mini_map_max_width  => 200;
Readonly my $mini_map_max_height => 200;
Readonly my $mini_map_name => "mini_map.png";

sub new {
  my ($class_name, $pdf_name) = @_;

  my ($base_name) = $pdf_name =~ m{(?:.*/)(.*)\.pdf$};
  my $tiles_subdir = "tiles";
  my $self = {
    pdf_name => $pdf_name,
    base_dir => $base_name,
    base_name => $base_name,
    rendered_dir => "$base_name/rendered",
    tiles_dir => "$base_name/$tiles_subdir",
    tiles_subdir => $tiles_subdir,
  };
  return bless $self, $class_name;
}

sub pdf_to_png {
  my $self = shift;
  my $base_dir = $self->{base_dir};
  my $file_base = $self->{base_name};
  my $rendered_dir = $self->{rendered_dir};
  my $pdf_name = $self->{pdf_name};
  my $error;
  my $info;

  my @image_file_names;

  # render at different resolutions
  my @dpiResolutions = qw(72 100 200 300);
  foreach my $dpi (@dpiResolutions) {
    system ("nice gs -q -dSAFER -dBATCH -dNOPAUSE " . 
              "-sDEVICE=png16m -dUseCropBox -dMaxBitmap=300000000 " .
              "-dFirstPage=1 -dLastPage=1 " .
              "-dTextAlphaBits=4 -dGraphicsAlphaBits=4 -dDOINTERPOLATE -r$dpi " .
              "-sOutputFile=$rendered_dir/$file_base.png $pdf_name");
    $info = image_info ("$rendered_dir/$file_base.png");
    if ($error = $info->{error}) {
      die "Can't parse image info: $error\n";
    }
    my ($width, $height) = dim ($info);
    my $dest_file_name = "${file_base}_w${width}_h${height}_dpi${dpi}.png";
    rename "$rendered_dir/$file_base.png", "$rendered_dir/$dest_file_name";
    print "rendered $dest_file_name\n";
    push @image_file_names, $dest_file_name;
  }

  return @image_file_names;
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
  my ($self, $file_name, $z)  = @_;

  my $rendered_dir = $self->{rendered_dir};
  my $tiles_dir = $self->{tiles_dir};
  my $base_name = $self->{base_name};
  my ($img_width, $img_height, $rendered_dpi) =
    $file_name =~ m/_w(\d+)_h(\d+)_dpi(\d+)\.(.*)$/;
  print "$base_name, $img_width, $img_height\n";
  my $img = Imager->new;
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr;

  my $tile_cnt = 0;
  my $max_y = $img_height / $tile_height;
  my $max_x = $img_width  / $tile_width;
  for   (my $y=0; $y < $max_y; $y++) {
    for (my $x=0; $x < $max_x;  $x++) {
      my $tile_img = $img->crop (left=>$x, top=>$y, 
                                width=> $tile_width, height => $tile_height);
      my $tile_name =
        "$tiles_dir/${base_name}_x" . $x . "y" . $y ."z$z.png";
      $tile_img->write (file => $tile_name)
        || die "Cannot write tile $x,$y: ". $tile_img->errstr();
      $tile_cnt++;
    }
    print "Finished row $y. Tiles written so far: $tile_cnt\n"
      if ($y & 0x1) == 0;   # even rows only
  }
  print "Total tiles written: $tile_cnt\n";
}

sub generate_javascript {
  my ($self, @file_names) = @_;
  my $pdf_name = $self->{pdf_name};
  my $rendered_dir = $self->{rendered_dir};
  my $base_dir = $self->{base_dir};
  my $error;
  my @dimensions;
  my $info;

  foreach my $file_name (@file_names) {
    $info = image_info("$rendered_dir/$file_name");
    die "Can't parse image info: $error\n" if ($error = $info->{error});
    my ($width, $height) = dim ($info);
    push @dimensions, { width => $width, height => $height };
  }
  $info = image_info("$rendered_dir/$mini_map_name");
  my ($mini_map_width, $mini_map_height) = dim($info);

  #print Dumper \@dimensions;

  my $tt = Template->new ();
  $tt->process(
        'ajax.xhtml.tt',
        {
          file_base => $self->{base_name},
          tiles_subdir => $self->{tiles_subdir},
          dimensions => \@dimensions,
          view_port_width  => 500,
          view_port_height => 400,
          mini_map_width  => $mini_map_width,
          mini_map_height => $mini_map_height,
        },
        "$base_dir/ajax.xhtml"
  ) || die $tt->error(), "\n";
}

sub generate {
  my $self = shift;
  mkdir $self->{base_dir} || die "Could not create base_dir\n";
  mkdir $self->{rendered_dir} || die "Could not create rendered_dir\n";
  mkdir $self->{tiles_dir} || die "Could not create tiles_dir\n";

  my @file_names = $self->pdf_to_png ();
  foreach my $i (0 .. $#file_names) {
    $self->tile_image ($file_names[$i], $i);
  }
  $self->create_mini_map ($file_names[-1]);   # Last one is typically largest
  $self->generate_javascript (@file_names);
}

1;