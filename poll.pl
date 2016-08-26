#!/usr/bin/perl

# This is a polling serving that will pick up any jobs in the queue

use warnings;
use strict;
use Fcntl qw(:seek :flock);
use Text::CSV;
use IO::File;
use CGI qw(url);
use POSIX qw(setsid);
use Fatal qw(open close seek truncate);
use Cwd qw(abs_path);
use File::Basename qw(dirname);
use Config::Std qw(read_config);
use Descartes::AjaxMapMaker;
use Descartes::Tools qw(get_now_string send_mail become_daemon open_pid_file);

my $descartes_dir = dirname(abs_path($0));
read_config "$descartes_dir/descartes.cfg" => my %config;
my $ajax_map_doc_root = $config{dir}{ajax_map_doc_root};
my $queue_data_file = "$ajax_map_doc_root/queue.dat";
my $log_data_file = "$descartes_dir/logs/log.dat";

my $fh = open_pid_file ('/var/tmp/descartes.pid');
my $pid = become_daemon(working_dir => $descartes_dir);
print $fh $pid;
close $fh;

while (1) {
  while (-e $queue_data_file && !-z $queue_data_file) {
    process_next_job();
  }
  print "Waiting for jobs. Sleeping for five seconds.\n";
  sleep (5);
}

sub process_next_job {
  my $F;
  my @jobs;

  open $F, '<', $queue_data_file;
  @jobs = <$F>;
  close $F;

  # Render the first job
  print @jobs;
  my $job = $jobs[0];
  my $csv = Text::CSV->new();
  $csv->parse($job);
  my ($date, $email, $source_file) = $csv->fields();
  my ($target_dir) = (-d $source_file)
                    ? ($source_file) :
                      $source_file =~ m{(.*)/[^/]+\z}xms;
  my $base_name;

  eval {
    my $map_maker
      = Descartes::AjaxMapMaker->new(
          "$ajax_map_doc_root/$source_file",
          "$ajax_map_doc_root/$target_dir",
        );
    $map_maker->generate();
    $base_name = $map_maker->get_base_name();
  };
  if ($@) {
    print STDERR "$@\n";
  }

  # Done rendering the first job. Now remove the first job from the queue.
  open $F, '+<', $queue_data_file;  # open for read/write
  flock $F, LOCK_EX;
  @jobs = <$F>;                # Must re-read @jobs in case new jobs were added
  shift @jobs;                 # Remove the first job; it is done.
  seek $F, 0, SEEK_SET;
  if (@jobs) {
    print $F @jobs;              # Write all jobs sans first job.
  }
  truncate($F, tell $F); # get rid of garbage at end of file.
  close $F;

  $csv->combine ($date, $email, $source_file, get_now_string() );
  open $F, '>>', $log_data_file;
  print $F $csv->string(), "\n";
  close $F;

  my $url_base = url (-base => 1);
  send_mail ($email, "Processing of $source_file is now done. " .
    "Your AJAX map is available at $url_base/$target_dir/$base_name");
}

