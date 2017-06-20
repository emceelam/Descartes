package Descartes::Lib;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw (
  refine_file_name
  get_config
);

use feature qw(state);
use JSON;
use File::Slurp qw(read_file);
use File::Basename qw(dirname);
use Data::Dumper;

# break an image file name into parts and refine the parts
# the parts are used to create file names for generated ajax map data
sub refine_file_name {
  my $source_file = shift;

  my ($refined_name, $file_ext) = $source_file =~ m{(?:.*/)?(.*)\.([^.]+)$};
    # almost File::Basename::fileparse(), but we exclude the file suffix '.'
  if (!$refined_name || !$file_ext) {
    return;
  }

  $refined_name =~ s/[^a-zA-Z0-9.\-]/_/g;
  $file_ext = lc $file_ext;

  if (wantarray()) {
    return $refined_name, $file_ext;
  }
  return $refined_name;
}

sub get_config {
  state $config;

  if (!$config) {
    my $dir = dirname(__FILE__);
    my $json_text = read_file ("$dir/config.json");
    $config = JSON->new()->relaxed()->decode($json_text);

    my @fields = qw(
      tile_size mini_map_max_width mini_map_max_height mini_map_name
      thumbnail_max_width thumbnail_max_height thumbnail_name
      low_res_max_width low_res_max_height tiles_subdir
    );
    foreach my $field (@fields) {
      die "config.json is missing $field"
        if !defined $config->{$field};
    }
  }
  return $config;
}

1;

