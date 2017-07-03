#!/usr/bin/env perl

use warnings;
use strict;
use Fatal qw( open close );

use Getopt::Long qw(:config gnu_getopt auto_help);
use Pod::Usage;
use Image::Info qw(image_type image_info dim);
use Template;
use Template::Stash::AutoEscape;
use Cwd qw(cwd abs_path);
use File::Basename qw(dirname);
use Text::Wrap qw(wrap);
use XML::Simple qw(XMLin XMLout);
use List::MoreUtils qw(firstval);
use Carp qw(croak);
use Math::Round qw(round);
use Path::Class qw(dir file);
use Log::Any ();
use Log::Any::Adapter;
use Data::Dumper;

use Descartes::MapMaker;
use Descartes::Lib qw(refine_file_name get_config get_share_dir);

pod2usage (-verbose => 1) if !@ARGV;

my $f_quiet = 0;
my $url_root = '';
my @source_files;
my @directories;
my @non_existents;
my @problem_files;
my @rendered_files;
my %gen_parms;
my $log = Log::Any->get_logger;
$Data::Dumper::Indent = 1;

GetOptions (
  'quiet'      => \$f_quiet,
  'scale:s'    => \&scaling,
  'url_root:s' => \$url_root,
  '<>' =>
    sub {
      my $obj = shift;
      my $stringified = "$obj";
      process_graphic_file ($stringified, \@source_files,
                           \@directories, \@non_existents,
                           \@problem_files, \@rendered_files);
    },
);

if (!$f_quiet) {
  Log::Any::Adapter->set('Stdout');
}

my $config = get_config();
my $mini_map_max_width  = $config->{mini_map_max_width};
my $mini_map_max_height = $config->{mini_map_max_height};
my $mini_map_name       = $config->{mini_map_name};

foreach my $source_file (@source_files) {
  $log->info("Rendering $source_file");
  eval {
    Descartes::MapMaker->new( source_file => $source_file )
                       ->generate(%gen_parms);
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
  $log->info("Rendered files");
  $log->info(join '', map {"  $_\n"} @rendered_files);
}
if (@non_existents) {
  $log->info("Non-existent files");
  $log->info(join '', map {"  $_\n"} @non_existents);
}
if (@problem_files) {
  $log->info("Problem files");
  foreach my $problem (@problem_files) {
    $log->info("  " . $problem->{file} . ":");
    $log->info(wrap ("    ", "    ", $problem->{error}));
  }
}

# make_gallery
# Take one directory full of graphic files. Call generate on each graphic file.
# Voila a gallery of slippy maps.
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
  my @all_files = readdir DIR;
  closedir DIR;
  my $gallery_file = firstval { $_ eq 'gallery.hiff' } @all_files;
  my $gallery;
  if (!$gallery_file) {
    $gallery = create_default_hiff ($gallery_dir, \@all_files);
  }
  else {
    $gallery = XMLin("$gallery_dir/$gallery_file",
                    KeyAttr => [],
                    ForceArray => ['item'],
                    #Cache => 'storable',
    );
    die "Could not XML process $gallery_dir/$gallery_file"
      if !$gallery;
  }

  my @graphic_files = grep { m/jpeg|jpg|gif|tif|png|pdf$/i } @all_files;
  my $items = $gallery->{item};
  my %gallery_items;
  @gallery_items{ map { $_->{dir} } @$items } = @$items;
  my @thumbs;
  foreach my $graphic_file (@graphic_files) {
    $log->info("Rendering $gallery_dir/$graphic_file");
    my $map_maker = Descartes::MapMaker->new(
      source_file => "$gallery_dir/$graphic_file",
      dest_dir    => $gallery_dir,
    );
    my $image_dir = $map_maker->generate(@gen_parms, f_zip => 0);
    my $generated_dir = "$gallery_dir/$image_dir";
    my $url_dir = $url_root ? "$url_root/$image_dir" : $image_dir;

    my $mini_map_file = "$generated_dir/rendered/$mini_map_name";
    my ($hi_res_file, $low_res_file, $scales)
        = get_all_res ("$generated_dir/rendered");
    my $scale_desc = join ', ', map { ($_ * 100) . '%' } @$scales;
    my $info = image_info ($mini_map_file);
    if (my $error = $info->{error}) {
       push @problem_files, {
         file => "$gallery_dir/$graphic_file",
         error => "Can't parse image info: $error",
       };
       next;
    }
    push @rendered_files, "$gallery_dir/$graphic_file";
    my($mini_map_width, $mini_map_height) = dim($info);

    push @thumbs, {
      src     => "$url_dir/rendered/$mini_map_name",
      caption => $graphic_file,
      width   => $mini_map_width,
      height  => $mini_map_height,
    };

    # augment the gallery items with extra meta data
    my $item = $gallery_items{$image_dir};
    $item->{thumb} = {
      src    => "$url_dir/rendered/$mini_map_name",
      width  => $mini_map_width,
      height => $mini_map_height,
    };
    $item->{multi_res}{file} = "$url_dir/index.html";
    $item->{multi_res}{scale_desc} = $scale_desc;
    $item->{low_res}{file} = "$url_dir/rendered/$low_res_file";
    $item->{low_res}{size}
      = round ((stat "$generated_dir/rendered/$low_res_file")[7] / 1024);
    $item->{hi_res}{file} = "$url_dir/rendered/$hi_res_file";
    $item->{hi_res}{size}
      = round ((stat "$generated_dir/rendered/$hi_res_file")[7] / 1024);
  }

  my $gallery_path = abs_path ($gallery_dir);
  my $share_dir    = get_share_dir();
  my $tt = Template->new ( {
    INCLUDE_PATH => $share_dir,
    OUTPUT_PATH  => $gallery_path,
    STASH        => Template::Stash::AutoEscape->new(),
  } );
  die ($Template::ERROR, "\n") if !$tt;

  my $tt_result = $tt->process(
        "gallery.html.tt",
        {
          thumbs => \@thumbs,
          mini_map_max_width  => $mini_map_max_width,
          mini_map_max_height => $mini_map_max_height,
          gallery => $gallery,
        },
        "index.html"
  );
  die ($tt->error() . "\n  Could not create $gallery_dir/index.html.\n")
    if !$tt_result;
}

sub scaling {
  my ($option, $scale_string) = @_;

  die "Scales '$scale_string' are supposed to be numbers\n" 
    if $scale_string !~ /\d/;
  $gen_parms{scales} = [ split /[\s,]+/, $scale_string ];
}

sub process_graphic_file {
  my ($source, $source_files, $directories, $non_existents, $problem_files)
    = @_;

  if (!-e $source) {
    push @$non_existents, $source;
    return;
  }
  if (-d $source) {
    $source =~ s{/$}{};
    push @$directories, $source;
    return;
  }

  if ($source !~ /\.pdf$/i) {
    my $type = image_type($source);
    if (my $error = $type->{error}) {
      push @$problem_files, {
        file => $source,
        error => "Can not determine file type: $error" 
      };
      return;
    }

    my $file_type = $type->{file_type};
    if ($file_type !~ m/GIF|PNG|JPEG|TIFF/) {
      push @$problem_files, {
        file => $source,
        error => "file type '$file_type': Not pdf, png, gif, tiff or jpg",
      };
      return;
    }
  }

  push @$source_files, $source;
}

sub create_default_hiff {
  my ($gallery_dir, $all_files) = @_;

  my $gallery = {};
  my @items;
  for my $file_name (@$all_files) {
    next if -d "$gallery_dir/$file_name";

    if (image_type($file_name)->{error}) {
      my $refined_name = refine_file_name ($file_name);
      push @items, {
        name => $file_name,
        desc => "Thumbnail description goes here",
        dir => $refined_name,
      };
    }
  }
  $gallery->{item} = \@items;
  open my $fh, '>', "$gallery_dir/gallery.hiff";
  my $return_val = XMLout ($gallery,
                        RootName => 'gallery',
                        KeyAttr => {'item' => 'dir' },
                        NoAttr => 1,
                        AttrIndent => 1,
                        XMLDecl => 1,
                        OutputFile => $fh,
                );
  close $fh;

  if (!$return_val) {
    die ("XMLout() fails");
  }
  return $gallery;
}

sub get_all_res {
  my $rendered_dir = shift;

  opendir (my $DIR, $rendered_dir)
    || croak "Could not open $rendered_dir: $!";
  my @dir_files = readdir $DIR;
  closedir $DIR;

  my $low_res_file = firstval { /^low_res[.][a-z]{3}$/ } @dir_files;
  my %scaled = map { /scale(\d+)[.][a-z]{3}$/ ? ($1,$_) : () } @dir_files;
  my @sorted_scales =  sort {$a<=>$b} keys %scaled;
  my $max_scale = $sorted_scales[-1];
  my $high_res_file = $scaled{$max_scale};

  return ($high_res_file, $low_res_file, [ map { $_ / 100 } @sorted_scales ] );
}

__END__

=head1 SYNOPSIS

make_slippy_map.pl [FILE]...

make_slippy_map.pl directory_of_graphic_files

=head2 DESCRIPTION

This program will take a hi-res graphics file (pdf, png, gif or jpg) and
generate a slippy map, also known
as google style map. If given a directory of graphics files, the generator will
generate a web page gallery of slippy maps.

You can see some examples at L<http://sjsutech.com/>

Perl module is available at L<https://stratopan.com/emceelam/descartes/master>

Warning: This software is Alpha. This software works best on the
author's Linux laptop, and has no testing on anyone else's machine.

=head2 ARGUMENTS

=over

=item --scale

Sets the scale factors for the renders. For example, 75%, 100%, 125% and 150% is
represented as 

  --scale=0.75,1,1.25,1.50

Please, no spaces.

=begin comment

=item --url_root (optional)

Specify an absolute url path of your gallery

  --url_root=http://localhost/gallery_path

Alternatively, specify the absolute path only, allowing the browser
to fill the http scheme and domain name.

  --url_root=/gallery_path

=end comment

=item --help

Print this help section

=item --quiet value

No output to stdout

=back

=head2 BUGS

may fail on raster graphics of less than 2000x2000

=cut

