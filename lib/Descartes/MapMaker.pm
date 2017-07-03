package Descartes::MapMaker;

use warnings;
use strict;
use Moose;
use namespace::autoclean;
use Imager;
use Image::Info qw(image_info dim);
use Template;
use Template::Stash::AutoEscape;
use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use File::Find qw(find);
use File::Copy qw(copy);
use File::Path qw(mkpath rmtree);
use File::Touch qw(touch);
use File::Basename qw(dirname);
use Params::Validate qw(validate ARRAYREF BOOLEAN SCALAR);
use Math::Round qw(round);
use Cwd qw(cwd abs_path);
use Carp qw(croak);
use Log::Any ();
use Data::Dumper;

use Descartes::Lib qw(refine_file_name get_config get_share_dir);

has 'source_file' => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has 'dest_dir' => (
  is        => 'ro',
  isa       => 'Str',
  builder   => '_build_dest_dir',
  predicate => 'has_dest_dir',
);

has 'descartes_dir' => (
  is      => 'ro',
  isa     => 'Str',
  default => sub { dirname (abs_path ($0))  },
);

has 'config' => (
  is      => 'ro',
  isa     => 'HashRef',
  lazy    => 1,
  builder => '_build_config',
);

has 'log' => (
  is      => 'ro',
  default => sub { Log::Any->get_logger },
);

has 'refined_name' => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_refined_name',
);

has 'base_dir' => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_base_dir',
);

has 'refined_dir' => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_refined_dir',
);

has 'rendered_dir' => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_rendered_dir',
);

has 'share_dir' => (
  is      => 'rw',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_share_dir',
);

has 'target_file_ext' => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_target_file_ext',
);

has 'scales' => (
  is      => 'rw',
  isa     => 'ArrayRef',
  default => sub { [] },
);

has 'previous_scale_renders' => (
  is      => 'rw',
  isa     => 'ArrayRef',
  lazy    => 1,
  builder => '_build_previous_scale_renders',
);

sub _build_dest_dir {
  my ($self) = @_;
  return $self->has_dest_dir() ? $self->dest_dir : '.';
}

sub _build_descartes_dir {
  my ($self) = @_;

  my $dest_dir = $self->has_dest_dir() ? $self->dest_dir : '.';
  $dest_dir =~ s|/$||;
  return $dest_dir;
}

sub _build_config {
  return get_config();
}

sub _build_refined_name {
  my ($self) = @_;
  my $refined_name = refine_file_name ($self->source_file);
  return $refined_name;
}

sub _build_base_dir {
  my ($self) = @_;
  my $refined_name = $self->refined_name;
  my $dest_dir     = $self->dest_dir;
  my $base_dir = "$dest_dir/$refined_name";
  return $base_dir;
}

sub _build_rendered_dir {
  my ($self) = @_;
  my $base_dir = $self->base_dir;
  return "$base_dir/rendered",
}

sub _build_share_dir {
  return get_share_dir();
}

sub _build_target_file_ext {
  my ($self) = @_;
  my $source_file = $self->source_file;
  my ($file_ext) = $source_file =~ m{\.([^.]+)$};

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

  return $sourceFileExt_to_targetFileExt{ $file_ext };
}


# Render the current pdf into multiple scales and
# return the scales and file names.
#   [ [ scale1, filename1 ],
#     [ scale2, filename2 ],
#     ... ]
sub pdf_to_png {
  my ($self) = @_;
  my $log          = $self->log;
  my $base_dir     = $self->base_dir;
  my $base_name    = $self->refined_name;
  my $rendered_dir = $self->rendered_dir;
  my $pdf_name     = $self->source_file;
  my $scales       = $self->scales;
  my $error;
  my $info;
  my @scale_and_files;
  my @renders;
  my $scale;
  my %seen;

  my $render_and_files = $self->previous_scale_renders;
  @renders = map { $_->[0] } @$render_and_files;
  @seen{@renders} = ();
  my @unrendered_scales = grep { !exists $seen{$_} } @$scales;

  # render at different resolutions
  # at scale 100%, monitor resolution is 72dpi
  foreach $scale (@unrendered_scales) {
    my $dpi = round($scale * 72);
    my $command
      = "pdftoppm -png -r $dpi -cropbox $pdf_name $rendered_dir/$base_name";
    $log->info($command);
    system ($command);

    my $page1_name  = "$rendered_dir/$base_name-1.png";
    my $output_name = "$rendered_dir/$base_name.png";
    if (-e $page1_name) {
      rename $page1_name, $output_name;
    }

    $info = image_info ($output_name);
    croak "Can't parse image info for $output_name: $error"
      if ($error = $info->{error});
    my ($width, $height) = dim ($info);
    my $percent_scale = $scale * 100;
    my $dest_file_name =
      "w${width}_h${height}_scale${percent_scale}.png";
    rename "$rendered_dir/$base_name.png", "$rendered_dir/$dest_file_name";
    $log->info("rendered $dest_file_name");
    push @scale_and_files, [ $scale, $dest_file_name ];
  }

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
  my $rendered_dir = $self->rendered_dir;
  my $log          = $self->log;

  return if is_up_to_date(
                  source => "$rendered_dir/$file_name",
                  target => "$rendered_dir/$target",
                );

  $log->info("Create $target based on $file_name");
  my $img = Imager->new();
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr . "\n";
  my $scaled_img = $img->scale (
                     xpixels => $p{max_width}, 
                     ypixels => $p{max_height},
                     type=>'min');

  $scaled_img->write (file => "$rendered_dir/$target")
    || die "Could not write $rendered_dir/$target: " . $scaled_img->errstr . "\n";
}

sub create_hi_res {
  my ($self, $file_name) = @_;
  my $rendered_dir = $self->rendered_dir;
  link $file_name, "$rendered_dir/hi_res" ||
    croak "could not link";
}

sub create_low_res {
  my ($self, $file_name) = @_;
  my $rendered_dir = $self->rendered_dir;
  my $log          = $self->log;
  my $ext          = $self->target_file_ext;
  my $low_res_name = "low_res.$ext"; 

  return if is_up_to_date(
                  source => "$rendered_dir/$file_name",
                  target => "$rendered_dir/$low_res_name",
                );

  $log->info("Rendering $rendered_dir/$low_res_name");
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

  my $config       = $self->config;
  my $rendered_dir = $self->rendered_dir;
  my $base_dir     = $self->base_dir;
  my $log          = $self->log;

  my $scale_dir = "$base_dir/scale" . ($scale * 100);
  if (is_up_to_date (
        source => "$rendered_dir/$file_name", target => $scale_dir)) {
    return;
  }
  mkpath ($scale_dir,1);

  # More variable initialization
  my $base_name = $self->refined_name;
  my $file_ext  = $self->target_file_ext;
  my ($img_width, $img_height) =
    $file_name =~ m/w(\d+)_h(\d+)_scale(?:\d+)\.(?:png|gif|jpg)$/;
  $log->info("$base_name, $img_width, $img_height");
  my $img = Imager->new;
  $img->read (file => "$rendered_dir/$file_name")
    || die "Could not read $rendered_dir/$file_name: " . $img->errstr;

  # Make the tiles
  my $tile_cnt = 0;
  my $tile_size = $config->{tile_size};
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
    if ( ($y & 0x1) == 0 ) {   # even rows only
      $log->info("Finished row $y. Tiles written so far: $tile_cnt");
    }
  }
  touch($scale_dir);
  $log->info("Total tiles written: $tile_cnt");
}

sub generate_html {
  my ($self, @file_names) = @_;
  my $rendered_dir = $self->rendered_dir;
  my $base_dir     = $self->base_dir;
  my $config       = $self->config;
  my $error;
  my @dimensions;
  my $info;

  foreach my $file_name (@file_names) {
    my ($width, $height, $scale) =
      $file_name =~ m/w(\d+)_h(\d+)_scale[0]*(\d+)\.(?:jpg|png|gif)$/;
    push @dimensions, { width => $width, height => $height, scale => $scale };
  }
  my $mini_map_name = $config->{mini_map_name};
  $info = image_info("$rendered_dir/$mini_map_name");
  croak ("image_info failed: " . $info->{error}) 
    if $info->{error};
  my ($mini_map_width, $mini_map_height) = dim($info);

  my $share_dir = $self->share_dir;
  my $tt = Template->new (
    INCLUDE_PATH => $share_dir,
    STASH        => Template::Stash::AutoEscape->new(),
  );
  my %template_to_output = (
    'slippy_map.html.tt' => 'index.html',
    'slippy_map.js.tt'   => 'slippy_map.js',
  );

  while (my ($template_file, $output_file) = each %template_to_output) {
    $tt->process(
        $template_file,
        {
          file_base        => $self->refined_name,
          tiles_subdir     => $config->{tiles_subdir},
          tile_size        => $config->{tile_size},
          tile_file_ext    => $self->target_file_ext,
          dimensions       => \@dimensions,
          view_port_width  => 500,
          view_port_height => 400,
          mini_map_width   => $mini_map_width,
          mini_map_height  => $mini_map_height,
        },
        "$base_dir/$output_file",
    ) || die "$share_dir/$template_file: " . $tt->error() . "\n";
  }
}

sub zip_files {
  my ($self) = @_;
  my $dest_dir  = $self->dest_dir;
  my $base_name = $self->refined_name;
  my $base_dir  = $base_name;
  my $log       = $self->log;
  my $zip = Archive::Zip->new();
  my $cwd = cwd();

  $log->info("creating zip archive");
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
  my $scales       = $self->scales;
  my $source_file  = $self->source_file;
  my $rendered_dir = $self->rendered_dir;
  my $base_name    = $self->refined_name;
  my $file_ext     = $self->target_file_ext;
  my $log          = $self->log;
  my ($width, $height);
  my $scale;
  my @scale_and_files;
  my $dest_file_name;

  my $render_and_files = $self->previous_scale_renders;
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
      $log->info("Copied $dest_file_name");
      copy $source_file, "$rendered_dir/$dest_file_name"
        || die "unable to write $dest_file_name\n";
    }
    else {
      $log->info("Rendered $dest_file_name");
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
  my $config = $self->config;
  my $thumbnail_name       = $config->{thumbnail_name};
  my $thumbnail_max_width  = $config->{thumbnail_max_width};
  my $thumbnail_max_height = $config->{thumbnail_max_height};

  # is the original file a pdf
  my $source_file = $self->source_file;
  my ($ext) = $source_file =~ m{\.([^.]+)$};
  my $f_pdf = $ext eq 'pdf';

  # scale settings
  my $scales = $p{scales};
  if (!$scales) {
    $scales = $f_pdf ? [1, 1.5, 2, 3] : [0.25, 0.5, 0.75, 1];
  }
  $self->scales($scales);

  mkpath ($self->rendered_dir, 1);
  if ($f_pdf) {
    $scale_and_files = $self->pdf_to_png ();
  }
  else {
    $scale_and_files = $self->scale_raster_image ();
  }
  foreach my $row (@$scale_and_files) {
    my ($scale, $file_name) = @$row;
    $self->tile_image ($scale, $file_name);
  }
  @file_names = map { $_->[1] } @$scale_and_files;
  my $source = $file_names[-1];
    # Create scaled down images based on the last file. Last is typically largest.
  my $mini_map_name       = $config->{mini_map_name};
  my $mini_map_max_width  = $config->{mini_map_max_width};
  my $mini_map_max_height = $config->{mini_map_max_height};
  $self->create_scaled_down_image (
    target => $mini_map_name, source => $source,
    max_width => $mini_map_max_width, max_height => $mini_map_max_height);
  $self->create_scaled_down_image (
    target => $thumbnail_name, source => $source,
    max_width => $thumbnail_max_width, max_height => $thumbnail_max_height);
  $self->create_scaled_down_image (
    target => "300x300.png", source => $source,
    max_width => 300, max_height => 300);
  $self->create_scaled_down_image (
    target => "285x285.png", source => $source,
    max_width => 285, max_height => 285);
  $self->create_hi_res  ($file_names[-1]);
  $self->create_low_res ($file_names[-1]);

  $self->generate_html (@file_names);
  if ($p{f_zip}) {
    $self->zip_files ();    # slow
  }

  # return the image directory where generated files are located
  return $self->refined_name;
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

sub _build_previous_scale_renders {
  my ($self) = @_;
  my @render_and_files;

  my $source       = $self->source_file;
  my $rendered_dir = $self->rendered_dir;
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

__PACKAGE__->meta->make_immutable;


1;