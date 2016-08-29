package Descartes::Lib;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw (
  refine_file_name
);

# break an image file name into parts and refine the parts
# the parts are used to create file names for generated ajax map data
sub refine_file_name {
  my $source_file = shift;

  my ($refined_name, $file_ext) = $source_file =~ m{(?:.*/)?(.*)\.([^.]+)$};
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



1;