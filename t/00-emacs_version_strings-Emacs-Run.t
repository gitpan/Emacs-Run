# Test file created outside of h2xs framework.
# Run this like so: `perl Emacs-Run.t'
#   doom@kzsu.stanford.edu     2008/03/08 06:36:39

#      ***dev_location***
#
# /home/doom/End/Cave/EmacsPerl/Wall/Emacs-Run/lib

use warnings;
use strict;
$|=1;
my $DEBUG = 0;  # TODO set to 0 before ship
use Data::Dumper;
use File::Copy qw( copy );
use Test::More;
BEGIN { plan tests => 19 };
use Test::Differences;

use FindBin qw( $Bin ); #
use lib "$Bin/../lib";

BEGIN {
  use_ok( 'Emacs::Run' );
}

ok(1, "Traditional: If we made it this far, we're ok.");

my $class = 'Emacs::Run';
{
  my $test_name = "Testing basic creation of object of $class";
  my $obj  = $class->new();
  my $type = ref( $obj );
  is( $type, $class, $test_name );
}

{
  my $test_name = "Testing emacs_version method";
  my $er = Emacs::Run->new();
  my $version = $er->emacs_version();

  like( $version, qr{ \d+ }msx ,
      "Testing that emacs major version looks numeric");

  like( $version, qr{ ^ 2[123] \. }msx ,
        "Testing that emacs major version is 21 or 22 or 23");
}


{
  my $test_name = "Testing emacs_version version string parsing";
  my $er = Emacs::Run->new();

  # TODO investigate what kind of versions are in use, at least with GNU/Emacs
  #      add cases here, and continue improving the parsing routine.
  my @expected_versions = qw(
                              21.0.0
                              23.2.1
                              21.4
                              22.1.1
                              22.1.92.1
                              23.0.0.1
                              21.4.1
                           );
  my %version_string;
  foreach my $ver (@expected_versions) {
    $version_string{ $ver } = qq{GNU Emacs $ver\n Blah blah};
  }

  my %version_string_xemacs;
  foreach my $ver (@expected_versions) {
    $version_string_xemacs{ $ver } = qq{Blah blah \nXEmacs $ver (patch 18) "Social Property" [Lucid] (amd64-debian-linux, Mule) of Wed Dec 21 2005 on yellow};
  }

  foreach my $ver (@expected_versions) {
    my $version = $er->parse_emacs_version_string( $version_string{ $ver } );
    is( $version, $ver, "$test_name: $ver");
  }

  foreach my $ver (@expected_versions) {
    my $version = $er->parse_emacs_version_string( $version_string_xemacs{ $ver } );
    is( $version, $ver, "$test_name: $ver");
  }
}


# ========
# end main, into the subs
