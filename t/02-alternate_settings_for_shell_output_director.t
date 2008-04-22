# Test file. Run this like so:
#   perl 02-alternate_settings_for_shell_output_director.t
# or use 'make test'
#   doom@kzsu.stanford.edu     2008/03/24 22:15:53

use warnings;
use strict;
$|=1;
my $DEBUG = 0;
use Data::Dumper;
use File::Copy qw( copy );
use File::Basename qw( fileparse basename dirname );
use Test::More;
use Test::Differences;

use FindBin qw( $Bin );
use lib "$Bin/../lib";
use lib "$Bin/lib";
use Emacs::Run::Testorama qw( :all );

# Globals
my $CLASS   = 'Emacs::Run';
my $SRC_LOC = "$Bin/dat/src";
my $USR     = "$Bin/dat/usr";

my $devnull = File::Spec->devnull;
my $emacs_found;
eval {
  $emacs_found = qx{ emacs --version 2>$devnull };
};
if($@) {
  $emacs_found = '';
  print STDERR "Problem with qx of emacs: $@\n" if $DEBUG;
}

if( not( $emacs_found ) ) {
  plan skip_all => 'emacs was not found in PATH';
} else {
  plan tests => 23;
}

use_ok( $CLASS );

ok(1, "Traditional: If we made it this far, we're ok."); #2

{#3, #4, #5
  my $method = "get_load_path";
  my $test_name = "Testing $method, with shell_output_director";

  my $mock_home = "$Bin/dat/home/mockingbird";
  my $code_lib = "$USR/lib";
  my $code_lib_alt = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my ($er, $load_path_aref, $expected_load_path_aref, $set);

  $er = Emacs::Run->new;
  $load_path_aref = $er->$method;
  print STDERR "\nload_path_aref:\n", Dumper($load_path_aref), "\n" if $DEBUG;
  $expected_load_path_aref =
    [
     '/tmp',
     "$code_lib",
     "$code_lib_alt",
     ];
  is_deeply( $load_path_aref, $expected_load_path_aref,
             "$test_name unset" );

  #4
  $set = '1>/dev/null 2>&1'; # toss all output
  $er = Emacs::Run->new;
  $load_path_aref = $er->$method({
                                     shell_output_director => $set
                                    });
  print STDERR "\nload_path_aref:\n", Dumper($load_path_aref), "\n" if $DEBUG;
  $expected_load_path_aref = [ ];
  is_deeply( $load_path_aref, $expected_load_path_aref,
             "$test_name set to $set on method" );

  #5
  $set = '1>/dev/null 2>&1'; # toss all output
  $er = Emacs::Run->new({
                         shell_output_director => $set
                        });
  $load_path_aref = $er->$method();
  print STDERR "\nload_path_aref:\n", Dumper($load_path_aref), "\n" if $DEBUG;
  $expected_load_path_aref =    [
                                 '/tmp',
                                 "$USR/lib",
                                 "$USR/lib-alt",
                                ];
  is_deeply( $load_path_aref, $expected_load_path_aref,
             "$test_name set in new, and hence ignored" );
}

{#6, #7, #8
  my $method = "get_variable";
  my $test_name = "Testing $method";

  my $mock_home     = "$Bin/dat/home/nicesuit";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-6-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  # print STDERR "Note: with emacs all variables are global & long names are wise...\n";

  # expected values for given names for each of the options_sets (defined below)
  my @name_value = (
   {
   'emacs-run-testorama-garudabird-knock-off-i-am-not-a-number-i-am-unique-dammit' =>
     '6',
   'emacs-run-testorama-tomb-of-the-unknown-varname' =>
     '',
    },
   {
   'emacs-run-testorama-garudabird-knock-off-i-am-not-a-number-i-am-unique-dammit' =>
     '6',
   'emacs-run-testorama-tomb-of-the-unknown-varname' =>
     '',
    },
   {
   'emacs-run-testorama-garudabird-knock-off-i-am-not-a-number-i-am-unique-dammit' =>
     "But I am not in error!\n6",
   'emacs-run-testorama-not-a-varname-really' =>
     "But I am not in error!\nSymbol's value as variable is void: emacs-run-testorama-not-a-varname-really",
    },
  );

  print STDERR "name_value array of hashrefs: \n" . Dumper(\@name_value) . "\n" if $DEBUG;

  my $sod = '2>&1';

  # pairs of options arrays, the first fed into new, the second fed into the method
  my @options_sets = (
                   [ {},                            {} ],
                   [ {shell_output_director=>$sod}, {} ],
                   [ {},                            {shell_output_director=>$sod} ],
                  );

  for my $i (0..2) {

    my $new_opts  = $options_sets[ $i ][0];
    my $meth_opts = $options_sets[ $i ][1];

 foreach my $varname (sort keys %{ $name_value[ $i ] }){
      my $er = Emacs::Run->new( $new_opts );
      my $result = $er->$method( $varname, $meth_opts );
      my $expected = $name_value[ $i ]->{ $varname };
      my $label = get_short_label_from_name( $varname );
      is( $result, $expected, "$test_name: $label, option set: $i" );
    }
  }
}

{
  my $test_name = "Testing run_elisp_on_file";

  my $mock_home     = "$Bin/dat/home/penguindust";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-5-template";
  my $src           = "$Bin/dat/src/text";
  my $arc           = "$Bin/dat/arc/text";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  my $test_subject = "chesterson.txt";
  my $source_file = "$src/$test_subject";
  my $test_subject_base = ( fileparse( $test_subject, qw{\.txt} ) )[0];
  my $result_file = "$mock_home/$test_subject_base-uc.txt";
  my $expected_file = "$arc/$test_subject_base-uc.txt";
  copy($source_file, $result_file) or die "$!";

  # we will now act on the "result" file
  my $filename = $result_file;

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;

  # Make the text upper case
  my $elisp = q{ (upcase-region (point-min) (point-max)) };

  my $ret = $er->run_elisp_on_file( $filename, $elisp );

  my ($result, $expected) = slurp_files( $result_file, $expected_file );

  eq_or_diff( $result, $expected,
              "$test_name: upcase-region on penguindust/chesterson.txt") or
                print STDERR "using emacs version: $emacs_found";

  # But that's not what we really care about just now... the return value is the thing:
  print STDERR "ret: $ret\n" if $DEBUG;

  my $expected_stderr = 'Yow! I am spewing to STDERR!  Can I register as an Anarchist?' . "\n";
     $expected_stderr .= qq{Wrote $result_file};

  is( $ret, $expected_stderr, "$test_name: captured message sent to stderr.");

  $er = Emacs::Run->new({
                         shell_output_director => '2>/dev/null',
                        });

  $ret = $er->run_elisp_on_file( $filename, $elisp );
  is( $ret, '', "$test_name: no messages from stderr (cut off at new).");

  $er = Emacs::Run->new();
  $ret = $er->run_elisp_on_file( $filename, $elisp,
                                 {
                                  shell_output_director => '2>/dev/null',
                                 } );

  is( $ret, '', "$test_name: no messages from stderr (cut off at method).");
}

# eval_function has a complicated expanded interface which must
# distinguish between these four cases:
#   scalar
#   scalar aref
#   scalar href
#   scalar aref href
# The aref can be used to pass (simple?) arguments to the function
# The options href can, of course, change the sod.

{
  my $test_name = "Testing eval_function interface";

  my $mock_home     = "$Bin/dat/home/honestpol";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-7-template";
  my $src           = "$Bin/dat/src/text";
  my $arc           = "$Bin/dat/arc/text";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  my $funclib       = "$mock_home/a_poor_thing.el";

  my $funcname1 = "emacs-run-testorama-23-sched-dolittle";
  my $funcname2 = "emacs-run-testorama-23-sched-doless";

  my $func1 =<<"ENDFUNC1";
  (defun $funcname1 (fing fang)
    \"Talks to stderr and stdout, fixed spew plus two echoes: FING and FANG.\"
    (message \"think blue\")
    (print \"count two\")
    (message \"%s\" fing)
    (print   fang))
ENDFUNC1

  my $func2 =<<"ENDFUNC2";
  (defun $funcname2 ()
    \"Talks to stderr and stdout, spew only.\"
    (message \"%s\" \"think blue\")
    (print \"count two\"))
ENDFUNC2

  open my $fh, '>', $funclib or die "$!";
  print {$fh} $func1, "\n";
  print {$fh} $func2, "\n";
  close $fh;

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new({
                            emacs_libs => [ $funclib ],
                           });

  # Need to cover roughly four cases:
  #   $er->eval_function( $funcname );
  #   $er->eval_function( $funcname, $args_aref );
  #   $er->eval_function( $funcname, $args_aref, $opts_href );
  #   $er->eval_function( $funcname, $opts_href );
  # Note these dump STDERR by default, so we'll use '2>&1' to mix in STDERR

  my $args_aref = ["oink", "proper campaign contributions to key races will ensure that business needs can be met"];

  my $opts_href = { shell_output_director => '2>&1',
                  };

  my $ret;
  $ret = $er->eval_function( $funcname2 );
  print STDERR "ret: $ret\n" if $DEBUG;
  unlike( $ret, qr{think blue}, "$test_name with no args or opts: ignores stderr (the default)");
  like(   $ret, qr{count two},        "$test_name with no args or opts: sees stdout");

  $ret = $er->eval_function( $funcname1, $args_aref );
  print STDERR "ret: $ret\n" if $DEBUG;
  unlike( $ret, qr{think blue|oink}, "$test_name with args: ignores stderr (the default)");
  like(   $ret, qr{$args_aref->[1]}, "$test_name with args: passes through an arg to stdout");

  $ret = $er->eval_function( $funcname1, $args_aref, $opts_href );
  print STDERR "ret: $ret\n" if $DEBUG;
  like( $ret, qr{think blue|oink}, "$test_name with args & opts: sees stderr now");
  like( $ret, qr{$args_aref->[1]}, "$test_name with args & opts: gets an arg to stdout");

  $ret = $er->eval_function( $funcname2, $opts_href );
  print STDERR "ret: $ret\n" if $DEBUG;
  like( $ret, qr{think blue}, "$test_name with opts: sees stderr");
  like( $ret, qr{count two},  "$test_name with opts: also sees stdout");
}
