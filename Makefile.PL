#!/usr/bin/env perl
# -*- mode: perl; -*-
use strict;
use warnings;
use ExtUtils::MakeMaker;

my $homepage = 'https://github.com/kiwiroy/mojolicious-command-author-generate-launchd';
my $main_module = 'lib/Mojolicious/Command/Author/generate/launchd.pm';
WriteMakefile(
    NAME          => 'Mojolicious::Command::Author::generate::launchd',
    AUTHOR        => 'Roy Storey <kiwiroy@cpan.org>',
    LICENSE       => 'artistic_2',
    ABSTRACT_FROM => $main_module,
    VERSION_FROM  => $main_module,
    EXE_FILES     => [qw{script/hypnotoad-launchd}],
    META_MERGE => {
        resources => {
            bugtracker => "${homepage}/issues",
            homepage   => "${homepage}",
            repository => "${homepage}.git",
        },
    },
    PREREQ_PM => {
        'File::Glob'  => '0',
        'File::Which' => '0',
        'Mojolicious' => '8.12',
        'Role::Tiny'  => '0',
    },
    BUILD_REQUIRES => {
        'Test::More' => '0.90',
        'Capture::Tiny' => '0',
    },
    # lower case
    test => {TESTS => (-e 'META.yml' ? 't/*.t' : 't/*.t xt/*.t')},
    dist => { ($^O eq 'darwin' ? (TAR => 'gnutar') : ())},
);

exit 0;
