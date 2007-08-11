#!/usr/bin/perl -w

use strict;
use Fcntl qw(:flock);
use CGI qw(:standard uploadInfo cgi_error);
use CGI::Carp qw(fatalsToBrowser);
use Data::Dumper;
use Data::FormValidator;
use Data::FormValidator::Constraints qw(email);
use Text::CSV qw();
use File::Path qw(mkpath);
use DateTime;
use Tools qw(get_now_string $ajax_map_doc_root);
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

my %profile = (
  required => [ qw/email1 email2 upload/ ],
  filters => ['trim', 'lc'],
  constraint_methods => {
    email1 => [ email(), \&email_match ],
    email2 => [ email(), \&email_match ],
  },
  msgs => {
    constraints => { email => 'mismatched e-mail address'}
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

  my $upload_path;
  if (!$dfv_error) {
    my $filename = param('upload');
    $fh = upload ('upload');
    die ("Could not Upload File: " . cgi_error() . "\n")
      if !$fh && cgi_error();
    my $upload_filename = (split m{/},$filename)[-1];
    my $email = param('email1');
    #my $user_directory = get_user_directory ($email);
    my $user_directory = "u/$email";
    my $ajax_map_dir = "$ajax_map_doc_root/$user_directory";
    $upload_path = "$ajax_map_dir/$upload_filename";
    mkpath ("$ajax_map_dir");
    open(F, '>', "$ajax_map_dir/$upload_filename");
    binmode $fh;
    binmode F;
    while (<$fh>) {
      print F;
    }
    close F;   # Yes, you need this close

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