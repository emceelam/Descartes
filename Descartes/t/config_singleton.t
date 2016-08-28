#!/usr/bin/perl

use warnings;
use strict;

use Descartes::ConfigSingleton;
use Data::Dumper;
use Test::More (tests => 2);

my $config_obj = new Descartes::ConfigSingleton;
my $config = $config_obj->config;


is (ref($config), 'HASH', "config is a hash ref");
ok ($config_obj->validate($config), "config validates correctly");



