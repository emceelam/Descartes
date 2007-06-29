package Tools;

use version; our $VERSION = qv('0.1');  # Must all be on same line
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw ( get_now_string send_mail $ajax_map_doc_root);

use DateTime;
use DateTime::Format::MySQL;
use Readonly;

Readonly our $ajax_map_doc_root => '/home/www/ajax_map';
Readonly our $home_time_zone => 'America/Los_Angeles';
use constant HOME_TIME_ZONE => 'America/Los_Angeles';

sub get_now_string {
  my $dt_now = DateTime->now(time_zone => $home_time_zone);
  return DateTime::Format::MySQL->format_datetime($dt_now);
}

sub send_mail {
  my ($to_email_addr, $message) = @_;
  my $from_email_addr = 'emceelam@warpmail.net';
  open(MAIL, "|/usr/lib/sendmail -oi -t -odq") || die "Can't open sendmail: $!";
print MAIL <<MESSAGE;
From: Emcee Lam <$from_email_addr>
To: $to_email_addr
Subject: Processing done

$message
MESSAGE
close(MAIL);
}



1;