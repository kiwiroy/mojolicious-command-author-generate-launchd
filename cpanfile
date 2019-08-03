requires 'File::Glob';
requires 'File::Which';
requires 'Mojolicious' => '8.12';
requires 'Role::Tiny';
requires 'perl' => '5.20.0';

test_requires 'Test::More';
test_requires 'Capture::Tiny';

on develop => sub {
  requires 'Devel::Cover' => 0;
  requires 'IO::Socket::SSL' => '2.009';
  requires 'Test::Pod' => 0;
  requires 'Test::Pod::Coverage' => 0;
  requires 'Test::CPAN::Changes' => 0;
  requires 'Devel::Cover::Report::Coveralls' => '0.11';
  requires 'Devel::Cover::Report::Kritika' => '0.05';
};
