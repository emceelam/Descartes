package Descartes::ConfigSingleton;

use MooseX::Singleton;
use JSON;
use File::Slurp qw(read_file);
use File::Basename qw(dirname);

has config => (
  is => 'ro',
  isa => 'HashRef',
  lazy => 1,
  builder => '_build_config',
);

sub validate {
  my ($self, $config) = @_;
  
  foreach my $k (qw(
    tile_size mini_map_max_width mini_map_max_height mini_map_name 
    thumbnail_max_width thumbnail_max_height thumbnail_name
    low_res_max_width low_res_max_height
  ))
  {
    return 0 if !defined $config->{$k};
  }
  return 1;
}

sub _build_config {
  my ($self) = @_;
  my $dir = dirname(__FILE__);
  my $json_text = read_file ("$dir/config.json");
  my $config = JSON->new()->relaxed()->decode($json_text);
  die "bad config.json" if !$self->validate($config);
  
  return $config;
};

1;