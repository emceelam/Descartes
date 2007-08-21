package Descartes::Tools;

use version; our $VERSION = qv('0.1');  # Must all be on same line
require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw ( get_now_string send_mail become_daemon open_pid_file
  $ajax_map_doc_root);

use DateTime;
use DateTime::Format::MySQL;
use Readonly;
use IO::File;
use POSIX qw(setsid);
use Params::Validate qw(validate SCALAR);

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

sub become_daemon {
  my %p = validate (@_, {
    working_dir => {
      type => SCALAR,
    },
  });
  my $child = fork();

  die "Can't fork" unless defined $child;
  exit 0 if $child;  # parent dies
  setsid ();    # become session leader
  open (STDIN, '<', '/dev/null');
  open (STDOUT, '>', '/dev/null');
  #open (STDERR, ">&STDOUT");
  chdir $p{working_dir};   # change working directory
  umask (0);   # forget file mode creation mask
  $ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';
  return $$;
}


sub open_pid_file {
  my $file = shift;
  if (-e $file) {
    my $fh = IO::File->new($file);
    return undef if !$fh;

    my $pid = <$fh>;
    die "Server already running with PID $pid\n" if kill 0, $pid;
    warn "Removing PID file for defunct server process $pid.\n";
    die  "Can't unlink PID file $file" unless -w $file && unlink $file;
  }
  return IO::File->new ($file, O_WRONLY|O_CREAT|O_EXCL, 0644)
    or die "Can't create $file: $!\n";
}


sub tell_admin {
  
}


1;