#!/usr/bin/perl -w

# This is a polling serving that will pick up any jobs in the queue

use strict;
use Fcntl qw(:seek :flock);
use Text::CSV;
use IO::File;
use DateTime;
use CGI qw(url);
use Fatal qw(open close seek truncate);
use AjaxMapMaker;
use Tools qw(get_now_string send_mail $ajax_map_doc_root);

my $queue_data_file = "queue.dat";
my $log_data_file = "log.dat";
my $target_dir = "target";

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
  ($target_dir) = (-d $source_file)
                    ? ($source_file) :
                      $source_file =~ m{(.*)/[^/]+\z}xms;
  my $ajax_target_dir = "$ajax_map_doc_root/$target_dir";

  eval {
    my $map_maker =
      AjaxMapMaker->new("$ajax_map_doc_root/$source_file", $ajax_target_dir);
    $map_maker->generate();
  };
  if ($@) {
    print "$@\n";
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
    "Your AJAX map is available at $url_base/$target_dir");
}

while (1) {
  while (!-z $queue_data_file) {
    process_next_job();
  }
  print "Waiting for jobs. Sleeping for five seconds.\n";
  sleep (5);
}