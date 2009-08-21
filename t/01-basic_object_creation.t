# Test file created by perlnow.el to work with oop code
# Run this like so: `perl 01-Bongo-Cupcakes-Splat.t'
#   doom@kzsu.stanford.edu     2009/08/20 21:03:51

use warnings;
use strict;
$|=1;
my $DEBUG = 1;             # TODO set to 0 before ship
use Data::Dumper;

use Test::More;
BEGIN { plan tests => 2 }; # TODO change to 'tests => last_test_to_print';

use FindBin qw( $Bin );
use lib "$Bin/../lib";

my $class;
BEGIN {
  $class = 'Emacs::Run';
  use_ok( $class );
}

{ my $test_name = "Testing creation of object of expected type: $class";
  my $obj = $class->new();
  my $created_class = ref $obj;
  is( $created_class, $class, $test_name );
}

# Insert your test code below.


