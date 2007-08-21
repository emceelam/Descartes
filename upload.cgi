#!/usr/bin/perl -w

use strict;
use Fcntl qw(:flock);
use CGI qw(:standard uploadInfo cgi_error);
#use CGI::Carp qw(fatalsToBrowser);
  # conflicts with Carp module over redefined functions
use Data::Dumper;
use Data::FormValidator;
use Data::FormValidator::Constraints qw(email);
use Data::FormValidator::Constraints::Upload qw(file_format);
use Text::CSV qw();
use File::Path qw(mkpath);
use File::Copy qw(copy);
use Math::Round qw(nearest);
use Image::Info qw(image_info dim);
use Image::Size qw(imgsize);
use Readonly;
use Descartes::Tools qw(get_now_string $ajax_map_doc_root);
use Fatal qw(open close);

print header();
print start_html("File Uploading");
print h1 "File Uploads";

sub email_duplicate_address {
  my ($email1, $email2) = @_;
  return $email1 eq $email2;
}

my %args;
foreach my $key (param()) {
  $args{$key} = param($key);
}

sub email_match {
  my $dfv = shift;
  my $data = $dfv->get_filtered_data();

  $dfv->set_current_constraint_name('email');
  return $data->{email1} eq $data->{email2}
}

# Used exclusively by Data::FormValidator
sub image_max_megapixels {
  my $max_megapixels = shift;

  return sub {
    my $dfv = shift;

    $dfv->set_current_constraint_name('megapixels');
    my $q = $dfv->get_input_data;
    my $field = $dfv->get_current_constraint_field;
    my $upload_name = $q->param($field);
    my $fh = $q->upload($upload_name);
    my ($width, $height) = imgsize($fh);

    # Give a pass if this file has no width or height
    # which is the case for pdf files.
    return 1 if !defined $width || !defined $height;

    my $megapixels = $width * $height / 1e6;
    return $max_megapixels > $megapixels;
  }
}

Readonly my $max_megapixels => 20;
my %profile = (
  required => [ qw/email1 email2 upload/ ],
  filters => ['trim', 'lc'],
  constraint_methods => {
    email1 => [ email(), \&email_match ],
    email2 => [ email(), \&email_match ],
    upload => [ file_format(mime_types =>
                             [ qw(image/jpeg image/gif image/png),
                               qw(image/tiff application/pdf) ] ),
                image_max_megapixels($max_megapixels) ],
  },
  msgs => {
    constraints => {
      email => 'mismatched e-mail address',
      file_format => 'unsupported file format',
      megapixels => "Image too large, too many pixels in image",
    }
  },
);
my $dfv_results;
my $dfv_error;
my $fh;

my $q = new CGI;
if (param ('submit')) {
  $dfv_results = Data::FormValidator->check($q, \%profile);
  if ($dfv_results->has_invalid() or $dfv_results->has_missing()) {
    $dfv_error = $dfv_results->msgs();
  }

  if (!$dfv_error) {
    eval {
  
      my $filename = param('upload');
      $fh = upload ('upload');
      binmode $fh;
      die ("Could not Upload File: " . cgi_error() . "\n")
        if !$fh && cgi_error();
      my $upload_filename = (split m{/},$filename)[-1];
      my $email = param('email1');
      my ($login, $email_domain_name) = split /@/, $email;
      my $user_directory = "u/$email_domain_name/$login";
      my $user_path = "$ajax_map_doc_root/$user_directory";
      my $upload_path = "$user_path/$upload_filename";
      mkpath ("$user_path");
      if (! copy ($fh, $upload_path)) {
        print STDERR "Could not write uploaded file to $upload_path\n";
        die "Could not upload file\n";
      }
  
      my $csv = Text::CSV->new();
      $csv->combine(get_now_string(), $email, "$user_directory/$upload_filename");
      my $line = $csv->string();
      open my $F, '>>', "$ajax_map_doc_root/queue.dat";
      flock $F, LOCK_EX;
      print $F "$line\n";
      close $F;
  
      print p qq {
        $filename has been submitted for processing. An e-mail will be sent
        to you when the processing is done. If you like, you can submit
        more images for conversion.
      };
    };
  }
  if ($@) {
    print STDERR "$@\n";
    $dfv_error->{upload} = $@;
  }
}

print p q{Upload your image file (pdf, jpg, png, gif) and system will
          create an AJAX map for you.
        };
print start_form();
print '<table border="0", cellpadding="0" cellspacing="3">';
print Tr td("e-mail address",
            $dfv_error->{email1}),
         td(textfield (-name=>'email1', -size=>40, -maxlength=>100));
print Tr td("e-mail address (again)",
            $dfv_error->{email2}),
         td(textfield (-name=>'email2', -size=>40, -maxlength=>100));
print Tr td("file to upload",
            $dfv_error->{upload}),
         td(filefield(-name => "upload", -size => 75));
print '</table>';
print submit(-name => "submit", -value => "Upload File");
print "</form>";

print "</html>";

sub get_user_directory {
  my $email = shift;

  my ($username,$domain) = split /@/, $email;
  my ($second_level_domain, $top_level_domain) = (split /[.]/, $domain)[-2,-1];

  return "u/$top_level_domain/$second_level_domain/$username";
}

sub get_url_base_path {
  my ($url_base_path) = url() =~ m{(.*)/[^/]*$};
  return $url_base_path;
}