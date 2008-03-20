# Test file created outside of h2xs framework.
# Run this like so: `perl Emacs-Run.t'
#   doom@kzsu.stanford.edu     2008/03/08 06:36:39

#      ***dev_location***
#
# /home/doom/End/Cave/EmacsPerl/Wall/Emacs-Run/lib

use warnings;
use strict;
$|=1;
my $DEBUG = 0;
use Data::Dumper;
use File::Copy qw( copy );
use Test::More;
BEGIN { plan tests => 26 };
use Test::Differences;

use FindBin qw( $Bin ); #
use lib "$Bin/../lib";

BEGIN {#1
  use_ok( 'Emacs::Run' );
}

ok(1, "Traditional: If we made it this far, we're ok."); #2

# Globals
my $CLASS   = 'Emacs::Run';
my $SRC_LOC = "$Bin/dat/src";
my $USR     = "$Bin/dat/usr";

{#3
  my $test_name = "Testing basic creation of object of $CLASS";
  my $obj  = $CLASS->new();
  my $type = ref( $obj );
  is( $type, $CLASS, $test_name );
}

{#4
  my $method = 'append_to_ec_lib_loader';
  my $test_name = "Testing special accessor $method";
  my $er  = Emacs::Run->new();

  $er->set_ec_lib_loader( "Start: " );
  $er->append_to_ec_lib_loader( " middle... " );
  $er->append_to_ec_lib_loader( " And end!" );

  my $expected = "Start:  middle...  And end!";
  my $ec_lib_loader = $er->ec_lib_loader;
  is( $ec_lib_loader, $expected, $test_name );
}

{#5
  my $method = "detect_lib";
  my $test_name = "Testing $method on default.el";

  my $mock_home = "$Bin/dat/home/marshgas";
  my $code_lib  = "$USR/lib";
  my $code_lib_alt = "$USR/lib-with-default";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-3-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er      = Emacs::Run->new;
  $er->genec_load_emacs_init;  # got to do this first, or detect_lib won't see .emacs.
  my $ret = $er->$method( 'default' );

  print STDERR "$method:\n---\n$ret\n---\n" if $DEBUG;

  ok( $ret, "$test_name");
}

{#6
  my $method = "genec_load_emacs_init";
  my $test_name = "Testing $method loading just a .emacs file";

  my $mock_home = "$Bin/dat/home/mockingbird";
  my $code_lib = "$USR/lib";
  my $code_lib_alt = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;  # Note, this calls genec_load_emacs_init indirectly
  my $ec_frag = $er->ec_lib_loader;

  my $expected =
    qq{ -l "$Bin/dat/home/mockingbird/.emacs" };

  is( $ec_frag, $expected, "$test_name");
}

{#7-9
  my $method = "detect_site_init";
  my $test_name = "Testing $method and so on:";

  my $mock_home = "$Bin/dat/home/falsenose";
  my $code_lib  = "$USR/lib";
  my $code_lib_alt = "$USR/lib-mock-system";  # has a site-start.el w/function erhard
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-3-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;

  # Forcing detect_site_init to use mock .emacs before searching for site-start.el
  my $before_hook = $er->genec_load_emacs_init;
  $er->set_before_hook( $before_hook );
  my $start_found_flag = $er->$method;
  ok( $start_found_flag, "$test_name: using before_hook, found start-init.el" ); #7
  my $ec_frag = $er->genec_load_emacs_init;
  print STDERR "ec_load_emacs_init:\n---\n$ec_frag\n---\n" if $DEBUG;

  my $expected_pat = qr{
       ^ \s* -l \s* "site-start" \s* -l \s* "$Bin/dat/home/falsenose/\.emacs"  \s* $
  }xms;

  like( $ec_frag, $expected_pat, "$test_name: genec_load_emacs_init looks good"); #8
  my $ret  = $er->eval_function( 'erhard' );
  $ret = clean_whitespace( $ret );
  chop( $ret ); # Yes, *chop*, not chomp.  What the hell is on the end of the line there?
  is( $ret, "Got it.", "$test_name: function defined in site-start.el");  #9
}

{#10
  my $method = "get_load_path";
  my $test_name = "Testing $method, which uses eval_emacs to shell out to emacs";

  my $mock_home = "$Bin/dat/home/mockingbird";
  my $code_lib = "$USR/lib";
  my $code_lib_alt = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;
  my $load_path_aref = $er->$method;

  print STDERR "\nload_path_aref:\n", Dumper($load_path_aref), "\n" if $DEBUG;

  my $expected_load_path_aref =
    [
     '/tmp',
     "$code_lib",
     "$code_lib_alt",
     ];

  is_deeply( $load_path_aref, $expected_load_path_aref, "$test_name" );
}

{#11, #12, #13
  my $method = "get_variable";
  my $test_name = "Testing $method";

  my $mock_home     = "$Bin/dat/home/nicesuit";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-2-template";

  my %name_value = (
   'emacs-run-testorama-garudabird-knock-off-i-am-not-a-number-i-am-unique-dammit' =>
     '6',
   'emacs-run-testorama-gadzornika-gadzooks-yowsa-mama-have-you-ever-seen-a-variable-like-me' =>
      "Only in Drupal.",
    "load-path" =>
        qq{("/tmp" "$USR/lib" "$USR/lib-alt")},
    );

  print STDERR "name_value: \n" . Dumper(\%name_value) . "\n" if $DEBUG;

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;

  foreach my $varname (keys %name_value){
    my $result = $er->$method( $varname );
    my $expected = $name_value{ $varname };
    is( $result, $expected, "$test_name: $varname" );
  }
}

{
  my $method = "eval_function";
  my $test_name = "Testing $method";

  my $mock_home     = "$Bin/dat/home/nicesuit";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-3-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;
  my $funcname = 'emacs-run-testorama-groatcakes-for-greatness-more-grease-please';
  my $expected = 'Hello';
  my $result = $er->$method( $funcname );
  is( $result, $expected, "$test_name: $funcname" );
}


{
  my $test_name = "Testing get_variable and eval_function for user email and name.";

  my $mock_home     = "$Bin/dat/home/nicesuit";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-3-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;
  my $username = $er->eval_function( 'user-full-name'    );
  my $email    = $er->get_variable(  'user-mail-address' );

  my $expected_user  = "Cheney's Demon";
  my $expected_email = 'beast@666.dis.org';

  is( $username, $expected_user,  "$test_name: user"  );
  is( $email,    $expected_email, "$test_name: email" );
}



{
  my $test_name = "Testing internal quoting handling on elisp";

  my $mock_home    = "$Bin/dat/home/nicesuit";
  my $code_lib     = "$USR/lib";
  my $code_lib_alt = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-3-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;
  my $elisp = q{ (message (mapconcat 'identity load-path " | ")) };
  my $result = $er->eval_elisp( $elisp );
  my $expected = "/tmp | $USR/lib | $USR/lib-alt";
  is( $result, $expected, "$test_name" );
}


{
  my $test_name = "Eval simple elisp with current user's actual emacs init files";
  my $er = Emacs::Run->new;
  my $result = $er->eval_elisp( '(message "yow")' );
  is( $result, "yow", $test_name );

  $result = $er->eval_elisp( '(print (+ 2 2))' );
  cmp_ok( $result, 'eq', '4', $test_name );
}

{
  my $test_name = "Testing run_elisp_on_file";

  my $mock_home     = "$Bin/dat/home/ghostcowboy";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-3-template";
  my $src           = "$Bin/dat/src/text";
  my $arc           = "$Bin/dat/arc/text";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  my $test_subject = "chesterson.txt";
  my $source_file = "$src/$test_subject";
  my $result_file = "$mock_home/$test_subject";
  my $expected_file = "$arc/$test_subject";
  copy($source_file, $result_file) or die "$!";

  # we will act on the "result" file
  my $filename = $result_file;

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $er = Emacs::Run->new;

  # Make every other word upper-case
  my $elisp = q{
          (while (progn
                   (upcase-word 1) (forward-word 1)
                   (not (looking-at "^$"))))
    };

  $er->run_elisp_on_file( $filename, $elisp );

  # open each file, slurp in.
  local $/; # mister slurpie
  open my $fh, "<", $result_file or die "$!";
  my $result = <$fh>;
  close( $fh );

  open $fh, "<", $expected_file or die "$!";
  my $expected = <$fh>;
  close( $fh );

  eq_or_diff( $result, $expected,
              "$test_name: checking contents of $result_file");
}

# Resurrecting a few tests for things in use by Emacs::Run::ExtractDocs

{
  my $method = "generate_elisp_to_load_library";
  my $test_name = "Testing $method on library name";

  my $mock_home     = "$Bin/dat/home/nowhereman";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $library_name = "nada";

  my $reed = Emacs::Run->new;
  my $elisp = $reed->$method($library_name);

  my $expected = qq{
     (progn
       (add-to-list 'load-path
         (expand-file-name "$code_lib/"))
         (load-file "$code_lib/nada.el"))
      };

  my $result_clean   = clean_whitespace( $elisp );
  my $expected_clean = clean_whitespace( $expected );

  is( $result_clean, $expected_clean, "$test_name" );
}

{
  my $method = "generate_elisp_to_load_library";
  my $test_name = "Testing the elisp returned from $method";

  my $mock_home     = "$Bin/dat/home/nowhereman";
  my $code_lib      = "$USR/lib";
  my $code_lib_alt  = "$USR/lib-alt";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-template";

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  my $library_name = "nada";

  my $reed = Emacs::Run->new;
  my $elisp = $reed->$method( $library_name );

  $elisp = $reed->quote_elisp( $elisp );

  # The generate $elisp should load the file nada.el, which should provide
  # the function nada-speaks, which returns (to STDERR) "Who you calling a dummy?"
  my $emacs_cmd = qq{
     emacs --batch --eval "$elisp" -f nada-speaks 2>&1
  };
  print STDERR "emacs_cmd: $emacs_cmd\n" if $DEBUG;

  # Process returned messages to get just the last line (and skip
  # the "Loading ..." messages and so on)
  my $ret = qx{ $emacs_cmd };
  my @lines = split /\n/, $ret;
  my $result = $lines[-1];
  my $expected = "Who you calling a dummy?";
  is( $result, $expected, "$test_name" );
}

{#23, #24, #25, #26
  my $test_name = "Testing lib_data attribute with type 'lib' using get_variable.";
  ## start with a simple load-path, then load an elisp library
  ## that adds another location, which will is used to load
  ## other libraries.

  my $mock_home     = "$Bin/dat/home/charlie_mccarthy";
  my $code_lib      = "$USR/lib-load-path-munge";
  my $code_lib_alt  = "$USR/lib-target";
  my $dot_emacs_tpl = "$SRC_LOC/templates/.emacs-4-template"; # minimal load path w/$code_lib only

  create_dot_emacs_in_mock_home( $mock_home, $code_lib, $code_lib_alt, $dot_emacs_tpl );

  # change the environment variable $HOME to point at the $mock_home
  $ENV{HOME} = $mock_home;
  echo_home() if $DEBUG;

  # A simple (?) way of passing a root location to my-load-path.el
  chdir($USR);

  # a shadowed.el exits in both lib-target and lib-load-path-munge.
  # they both define the variable "*-shadow" as different strings.
  my $lib_data = [
                  ['my-load-path', { type=>'lib', priority=>'requested' }],
                  ['shadowed',     { type=>'lib', priority=>'requested' }],
                 ];

  my $er = Emacs::Run->new (
                            {
                             lib_data => $lib_data,
                            }
                           );

  my $varname = 'emacs-run-testorama-shadow';
  my $value    = $er->get_variable( $varname );

  my $expected  = "Barnabas";
  is( $value, $expected,  "$test_name: $varname : $value"  );

  #24 -- without "my_load_path.el", we find a different shadowed.el
  $lib_data = [
                  ["shadowed", { type=>'lib', priority=>'requested' }],
                 ];

  $er = Emacs::Run->new (
                            {
                             lib_data => $lib_data,
                            }
                           );

  $varname = 'emacs-run-testorama-shadow';
  $value    = $er->get_variable( $varname );

  $expected  = "Lamont";
  is( $value, $expected,  "$test_name: $varname : $value"  );


  #25 -- type "file" adds it's location to load-path,
  #      enables a search for still another lib
  $test_name = "Testing that lib_data with type 'file' effects load-path.";
  print STDERR "\nYou may see some odd messages relating to null.el.  They can be ignored.\n";
  $lib_data = [
                  ["$USR/lib-alpha/null.el",
                    { type=>'file', priority=>'requested' }],
                  ["payload",
                    { type=>'lib', priority=>'requested' }],
                 ];

  $er = Emacs::Run->new (
                            {
                             lib_data => $lib_data,
                            }
                           );

  $varname = 'emacs-run-testorama-kandor';
  $value    = $er->get_variable( $varname );

  $expected  = "Keep it bottled up.";
  is( $value, $expected,  "$test_name: $varname : $value"  );

  #26 - use simpler emacs_libs rather than explicit lib_data
  # A replay of a test above: "a shadowed.el exits in both
  # lib-target and lib-load-path-munge.  they both define the
  # variable "*-shadow" as different strings."
  $test_name = "Testing that emacs_libs works also.";
  $er = Emacs::Run->new ( { emacs_libs => [ 'my-load-path', 'shadowed'], } );

  $varname = 'emacs-run-testorama-shadow';
  $value    = $er->get_variable( $varname );

  $expected  = "Barnabas";
  is( $value, $expected,  "$test_name: $varname : $value"  );
}





# ========
# ========
# end main, into the subs

# trims leading and trailing whitespace on multi-line text.
# eliminates blank lines.
# this is used to make it eaisier to compare generated and expected elisp
sub clean_whitespace {
  my $text = shift;
  my $output;
  my @lines = split /\n/, $text;
  foreach my $line (@lines) {
    $line =~ s{^\s+}{}xms;
    $line =~ s{\s+$}{}xms;
    next if ($line =~ m{^ \s* $}xms);
    $output .= "$line\n";
  }
  return $output;
}

# create a .emacs for $mock_home
sub create_dot_emacs_in_mock_home {
  my $mock_home     = shift;
  my $code_lib      = shift;
  my $code_lib_alt  = shift;
  my $dot_emacs_tpl = shift;

  if ($DEBUG) {
    print STDERR "mock_home: $mock_home\n";
    print STDERR "code_lib: $code_lib\n";
    print STDERR "code_lib_alt: $code_lib_alt\n";
    print STDERR "dot_emacs_tpl: $dot_emacs_tpl\n";
  }

  # read in template used to create a mock .emacs
  open my $fh_in, "<", $dot_emacs_tpl
    or die "Could not open $dot_emacs_tpl for read:$!";

  my $slurpie;
  {
    undef $/;
    $slurpie =<$fh_in>;
  }

  # munge template placeholders XXX and YYY with mock library locations.
  $slurpie =~ s{XXX}{$code_lib}xmsg;
  $slurpie =~ s{YYY}{$code_lib_alt}xmsg;

  # output the mock .emacs file in the mock home directory
  my $dot_emacs = "$mock_home/.emacs";
  open my $fh_out, ">", $dot_emacs
    or die "Could not open $dot_emacs for read:$!";

  print {$fh_out} $slurpie;
  close($fh_out);

  return $dot_emacs;
}


sub echo_home {
  print STDERR "HOME is now: $ENV{HOME}\n";
}

