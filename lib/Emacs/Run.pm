package Emacs::Run;
use base qw( Class::Base );

=head1 NAME

Emacs::Run - utilities to assist in using emacs from perl via the shell

=head1 SYNOPSIS

   use Emacs::Run;
   my $er = Emacs::Run->new();
   my $major_version = $er->emacs_version;
   if ($major_version > 22) {
      print "You have a recent version of emacs\n";
   }

   # quickly specify additional elisp libraries to use, then get information about emacs settings
   my $er = Emacs::Run->new({
                         emacs_libs => [ '~/lib/my-elisp.el', '/usr/lib/site-emacs/stuff.el' ],
                          });
   my $emacs_load_path_aref = $er->get_load_path;
   my $email = $er->get_variable(  'user-mail-address' );
   my $name  = $er->eval_function( 'user-full-name'    );


   # suppress the use of the usual emacs init (e.g. ~/.emacs)
   my $er = Emacs::Run->new({
                       load_emacs_init => 0,
                    });
   my $result = $er->eval_elisp( '(print (+ 2 2))' );  # "4", in case you were wondering


   # Specify in detail which emacs lisp libraries should be loaded
   $lib_data = [
       [ 'dired',                 { type=>'lib',  priority=>'needed'    } ],
       [ '/tmp/my-load-path.el',  { type=>'file', priority=>'requested' } ],
       [ '/tmp/my-elisp.el',      { type=>'file', priority=>'needed'    } ],
     ];
   my $er = Emacs::Run->new({
                       lib_data => $lib_data,
                    });
   my $result = $er->eval_lisp( qq{ (print (my-elisp-run-my-code "$perl_string")) } );



=head1 DESCRIPTION

Emacs::Run is a module that provides utilities to work with
emacs when run from perl as an external process.

The emacs "editor" has some command-line options ("--batch" and so
on) that allow you to use it as a lisp interpreter and run elisp
code non-interactively.

This module provides methods that use these features of emacs for
two types of tasks:

=over

=item *

Probe your emacs installation to get the installed version, the
user's current load-path, and so on.

=item *

Run chunks of emacs lisp code without worrying too much about the
details of quoting issues and loading libraries and so on.

=back

=head2 METHODS

=over

=cut

use 5.8.0;
use strict;
use warnings;
use Carp;
use Data::Dumper;
use Hash::Util      qw( lock_keys unlock_keys );
use File::Basename  qw( fileparse basename dirname );
use List::Util      qw( first );
use Env             qw( $HOME );
use List::MoreUtils qw( any );

our $VERSION = '0.01';
my $DEBUG = 0;

# needed for accessor generation
our $AUTOLOAD;
my %ATTRIBUTES = ();


=item new

Creates a new Emacs::Run object.

Takes a hashref as an argument, with named fields identical
to the names of the object attributes. These attributes are:

=over

=item emacs_path

By default, this code looks for an external program in the
PATH envar called 'emacs'.  If you have multiple emacsen
installed in different places and/or under different names,
you can choose which one will be used by setting this
attribute.

=item emacs_version

The version of emacs in use.  Set automatically by the
"probe_emacs_version" method during object initialization.

=item emacs_type

The flavor of emacs in use, e.g. 'Gnu Emacs'.  Set automatically by
the "probe_emacs_version" method during object initialization.

=item load_emacs_init

Defaults to 1, if set to a false value, will suppress the use
of the user's emacs init file (e.g. "~/.emacs").

=item load_site_init

Defaults to 1, if set to a false value, will suppress the use
of the system "site-start.el" file (which loads before the
user's init file).

=item load_default_init

Defaults to 1, if set to a false value, will suppress the use
of the system "default.el" file (which loads after the user's
init file).

=item load_no_inits

A convenience flag, used to disable all three types of emacs init
files in one step when set to a true value.  Overrides the other three.

=item requested_libs

A list (aref) of elisp library names that the system will attempt
to load if they can be found (by searching the load-path).
E.g. "dired"

=item requested_elisp_files

A list (aref) of elisp library file names (with paths) that
the system will attempt to load if they exist on the file
system.  E.g. "~/lib/my-dired-helper.el"

=item needed_libs

Like "requested_libs", except that the system throws an error
if a library can not be found.

=item needed_elisp_files

Like "requested_elisp_files", except that the system throws an error
if a library can not be found.

=item emacs_libs

A list of emacs libraries (with or without paths) to be loaded
automatically.  This is provided as a convenience for quick use.
To take full control over how your emacs libraries are handled,
see L</lib_data>.

=item lib_data

This is a more complicated data structure than L</emacs_libs>: an
array of arrays of two elements each, the first element is the
library name (a string, with or without path), the second element
is a hash of library attributes: 'priority' which can be 'requested' or
'needed' and 'type' which can be 'file' or 'lib'.

Example:

  $lib_data = [
    [ 'dired',                 { type=>'lib',  priority=>'needed'    } ],
    [ '/tmp/my-load-path.el',  { type=>'file', priority=>'requested' } ],
    [ '/tmp/my-elisp.el',      { type=>'file', priority=>'needed'    } ],
  ];

emacs library attributes:

=over

=item priority

A 'requested' library will be silently skipped if it is not
available (and any elisp code using it may need to do something
like 'featurep' checks to adapt to it's absence).  A 'needed' file
will cause an error to occur if it is not available.  The default
priority is 'requested', but that can be changed via the L</default_priority>
attribute.

=item type

A library of type 'file' should be a filesystem path to a file
containing a library of emacs lisp code.  A library of type 'lib'
is specified by just the basename of the file (sans path or extension),
and we will search for it looking in the places specified in the emacs
variable load-path.  If neither is specified, the system will
guess the lib is a file if it looks like it has a path and/or extension.

=back

If both lib_data and emacs_libs are used, the lib_data libraries
are loaded first, followed by the emacs_libs libraries.

=item default_priority

Normally this is set to "requested", but it can be set to "needed".

=item before_hook

A string inserted into the built-up emacs commands immediately
after "--batch", but before any other pieces are executed.
This is a good place to insert additional invocation options
such as "--multibyte" or "--unibyte".

=back

There are also a number of object attributes intended largely for
internal use.  The client programmer has access to these, but
is not expected to need it.  These are documented in L</internal attributes>.

=cut

# Note: "new" is inherited from Class::Base and
# calls the following "init" routine automatically.

=item init

Method that initializes object attributes and then locks them
down to prevent accidental creation of new ones.

Any class that inherits from this one should have an L</init> of
it's own that calls this L</init>.

=cut

sub init {
  my $self = shift;
  my $args = shift;
  unlock_keys( %{ $self } );

  if ($DEBUG) {
    $self->debugging(1);
  }

  # enter object attributes here, including arguments that become attributes
  my @attributes = qw(
                       emacs_path
                       emacs_version
                       emacs_major_version
                       emacs_type

                       load_emacs_init
                       load_site_init
                       load_default_init
                       load_no_inits

                       needed_libs
                       needed_elisp_files
                       requested_libs
                       requested_elisp_files

                       emacs_libs
                       lib_data
                       default_priority

                       before_hook

                       ec_lib_loader
                      );

  foreach my $field (@attributes) {
    $ATTRIBUTES{ $field } = 1;
    $self->{ $field } = $args->{ $field };
  }

  ## Define attributes (apply defaults, etc)

  $self->{ec_lib_loader} = '';

  # If we weren't given a path, let the $PATH sort it out
  $self->set_emacs_path('emacs') unless $self->emacs_path;

  # Determine the emacs version if we haven't been told already
  my $emacs_version =
    $self->emacs_version || $self->probe_emacs_version;
  $self->set_emacs_version( $emacs_version );

  # By default, we like to load all init files
  $self->{load_emacs_init}   = 1 unless defined( $self->{load_emacs_init}   );
  $self->{load_site_init}    = 1 unless defined( $self->{load_site_init}    );
  $self->{load_default_init} = 1 unless defined( $self->{load_default_init} );

  if( $self->{load_no_inits} ) {
    $self->{load_emacs_init}   = 0;
    $self->{load_site_init}    = 0;
    $self->{load_default_init} = 0;
  }

  $self->{ before_hook } ||= '';
  if($self->{load_no_inits} ) {
    $self->append_to_before_hook( ' -Q ' );
  }

  $self->{ default_priority } ||= 'requested';

  if( defined( my $emacs_libs = $self->{ emacs_libs } ) ) {
    $self->process_emacs_libs( $emacs_libs );
  }

  $self->set_up_ec_lib_loader;

  lock_keys( %{ $self } );
  return $self;
}

=item get_load_path

Returns the load-path from emacs (by default, using the
user's .emacs, if it can be found) as a reference to a perl array.

Changing the $HOME environment variable before running this method
results in loading the .emacs file located in the new $HOME.

=cut

sub get_load_path {
  my $self = shift;

  my $elisp = q{ (message (mapconcat 'identity load-path "\n")) };
  my $return = $self->eval_elisp( $elisp );

  my @load_path = split /\n/, $return;
  \@load_path;
}


=item get_variable

Given the name of an emacs variable, returns the value from
emacs (when started with the the .emacs located in $HOME,
if one is found),

Internally, this uses the emacs 'print' function, which can
handle variables containing complex data types, but the
return value will be a "printed representation" that may
make more sense to emacs than to perl code.  For example,
the "load-path" variable might look like:

  ("/home/grunt/lib" "/usr/lib/emacs/site-lisp" "/home/xtra/lib")

=cut

sub get_variable {
  my $self    = shift;
  my $varname = shift;
  my $subname = ( caller(0) )[3];

  my $elisp = qq{ (print $varname) };

#  my $return = $self->eval_elisp( $elisp );
  my $return = $self->eval_elisp_skip_err( $elisp );

  return $return;
}



=item eval_function

Given the name of an emacs function, this runs the function
(without arguments) and returns the value from emacs
(when started with the the .emacs located in $HOME, if one
is found).

As with L</get_variable>, this uses the emacs 'print'
function internally.

The returned output intermixes STDOUT and STDERR.

=cut

sub eval_function {
  my $self = shift;
  my $funcname = shift;
  my $subname = ( caller(0) )[3];

  my $elisp = qq{ (print ($funcname)) };

  my $return = $self->eval_elisp( $elisp );

  return $return;
}

=back

=head2 running elisp

=over


=item run_elisp_on_file

Given a file name, and some emacs lisp code (which presumably
modifies the current buffer), this method opens the file, runs
the code on it, and then saves the file.

Example usage:
  $self->run_elisp_on_file( $filename, $elisp );

=cut

sub run_elisp_on_file {
  my $self     = shift;
  my $filename = shift;
  my $elisp    = shift;
  my $subname  = ( caller(0) )[3];

  $elisp = $self->quote_elisp( $elisp );

  my $emacs       = $self->emacs_path;
  my $before_hook = $self->before_hook;

  # Covering a gnu emacs 21 stupidity: need "--no-splash"
  if ( $self->emacs_major_version eq '21' &&
       $self->emacs_type eq 'GNU Emacs' ) {
    $before_hook .= ' --no-splash ';
  }

  my $ec_head = qq{ $emacs --batch $before_hook --file='$filename' };

  my $ec_tail = qq{ --eval "$elisp" -f save-buffer 2>&1 };

  my $ec_lib_loader = $self->ec_lib_loader;

  my $emacs_cmd = "$ec_head $ec_lib_loader $ec_tail";

  $self->debug("$subname: emacs_cmd: $emacs_cmd");

  my $return = qx{ $emacs_cmd };
  $return = $self->clean_return_value( $return );

  $self->debug( "$subname return:\n===\n$return\n===\n" );

  return $return;
}

=item eval_elisp

Given string containing a chunk of elisp code this method
runs it by invoking emacs in batch mode, by default first
loading the user's initialization file ("$HOME/.emacs") if
it can be found.

Further, it will also load the libraries listed
in the L</requested_libs> attribute (if they can be found
in the emacs load-path), and it will load the files of elisp
code listed in the L</requested_elisp_files> attribute
(if they exist, whether or not they're present in the load-path).

If the L</load_emacs_init> attribute has been turned off, it
will not try to load the .emacs file, and similarly if the
L</load_site_init> has been turned off, it will avoid loading
the site-start.el file.

This method returns the output from the elisp code with
STDOUT and STDERR mixed together.  (Note: the emacs functions
'message' and 'print' both work to generate output.)

Example:

  my $result = $er->eval_elisp( '(print (+ 2 2))' );

=cut

sub eval_elisp {
  my $self  = shift;
  my $elisp = shift;
  my $subname = ( caller(0) )[3];
  $elisp = $self->quote_elisp( $elisp );

  my $emacs = $self->emacs_path;
  my $before_hook = $self->before_hook;

  my $ec_head = qq{ $emacs --batch $before_hook };
  my $ec_tail = qq{ --eval "$elisp" 2>&1 };

  my $ec_lib_loader = $self->set_up_ec_lib_loader;

  my $emacs_cmd = "$ec_head $ec_lib_loader $ec_tail";

  $self->debug("$subname: emacs_cmd:\n $emacs_cmd\n");

  my $return = qx{ $emacs_cmd };
  $return = $self->clean_return_value( $return );

  $self->debug( "$subname return:\n===\n$return\n===\n" );

  return $return;
}


=item eval_elisp_skip_err

Identical to L</eval_elisp>, except that it returns only
the standard output, ignoring any messages sent to STDERR.

=cut

sub eval_elisp_skip_err {
  my $self = shift;
  my $elisp = shift;
  my $subname = ( caller(0) )[3];
  $elisp = $self->quote_elisp( $elisp );

  my $emacs = $self->emacs_path;
  my $before_hook = $self->before_hook;

  my $ec_head = qq{ $emacs --batch $before_hook };
  my $ec_tail = qq{ --eval "$elisp" };

  my $ec_lib_loader = $self->set_up_ec_lib_loader;

  my $emacs_cmd = "$ec_head $ec_lib_loader $ec_tail";

  $self->debug("$subname: emacs_cmd:\n $emacs_cmd\n");

  my $return = qx{ $emacs_cmd };
  $return = $self->clean_return_value( $return );

  $self->debug( "$subname return:\n===\n$return\n===\n" );

  return $return;
}



=back

=head2 utility methods (largely, but not entirely for internal use)

=over

=item quote_elisp

Routine to quote elisp code before feeding it into an emacs
batch shell command.  Used internally by L</eval_elisp>.

This just adds a single backslash to all the double-quote
characters (an empirically determined algorithm, i.e. hack).

Example usage:

  $elisp = $self->quote_elisp( $elisp );
  $emacs_cmd = qq{ emacs --batch --eval "$elisp" 2>&1 };
  my $return = qx{ $emacs_cmd };

=cut

sub quote_elisp {
  my $self = shift;
  my $elisp = shift;

  $elisp =~ s{"}{\\"}xmsg; # add one backwhack to the double-quotes

  return $elisp;
}

=item qx_clean

Executes the given emacs shell invocation string, and returns
a cleaned up version of it's returned value.  This is intended
to be used with elisp that uses the 'print' function, which
has spurious leading and trailing newlines and double-quotes.

=cut

sub qx_clean {
  my $self       = shift;
  my $emacs_cmd  = shift;
  my $return = qx{ $emacs_cmd };
  $return = $self->clean_return_value( $return );
  return $return;
}



=item clean_return_value

Cleans up a given string, trimming unwanted leading and trailing
blanks and double quotes.

This is intended to be used with elisp that uses the 'print'
function.

=cut

sub clean_return_value {
  my $self = shift;
  my $string = shift;
  $string =~ s{^[\s"]+}{}xms;
  $string =~ s{[\s"]+$}{}xms;
  return $string;
}

=back

=head1 internal methods

The following routines are largely just used in the object
initialization phase.

=over

=item process_emacs_libs

Goes through the given list of emacs_libs, and converts the names into
the lib_data style of data structure, appending it to lib_data.

Returns a reference to a structure containing the new additions to lib_data.

=cut

# Note: since set_up_ec_lib_loader qualifies the data and fills in
# likely values for type and priority, it need not be done here.
sub process_emacs_libs {
  my $self = shift;
  my $libs = shift;

  my @new_lib_data;
  foreach my $name ( @{ $libs } ) {
    my $rec = [ $name,  { type=>undef, priority=>undef } ];
    push @new_lib_data, $rec;
  }

  my $lib_data = $self->lib_data;
  push @{ $lib_data }, @new_lib_data;
  $self->set_lib_data( $lib_data );

  return \@new_lib_data;
}



=item set_up_ec_lib_loader

Initializes the ec_lib_loader attribute by scanning for the
appropriate emacs init file(s) and processing the list(s) of emacs
libraries specified in the object data.

Returns the newly defined $ec_lib_loader string.

This routine is called by L</init> during object initialization.

=cut

sub set_up_ec_lib_loader {
  my $self = shift;

  $self->genec_load_emacs_init;

  my $lib_data = $self->lib_data;

  foreach my $rec (@{ $lib_data }) {

    my $name     = $rec->[0];
    my $type     = $rec->[1]->{type};      # file/lib
    my $priority = $rec->[1]->{priority};  # needed/requested

    # qualify the lib_data
    unless ( $type ) {
      $type = $self->guess_type_from_name( $name );
      $rec->[1]->{type} = $type;
    }
    unless ( $priority ) {
      $priority = $self->default_priority;
      $rec->[1]->{priority} = $priority;
    }

    my $method = sprintf "genec_loader_%s_%s", $type, $priority;
    $self->$method( $name );   # appends to ec_lib_loader
  }

  my $ec_lib_loader = $self->ec_lib_loader;

  return $ec_lib_loader;
}

=item genec_load_emacs_init

Generates a fragment of emacs command line to load the
emacs_init file(s) as appropriate.

=cut

sub genec_load_emacs_init {
  my $self = shift;

  # start from clean slate
  my $ec_lib_loader = $self->set_ec_lib_loader( '' );

  my $load_no_inits     = $self->load_no_inits;
  if ( $load_no_inits ) {
    return $ec_lib_loader; # empty string
  }

  my $load_emacs_init   = $self->load_emacs_init;
  my $load_site_init    = $self->load_site_init;
  my $load_default_init = $self->load_default_init;

  if ( ( $load_site_init ) && ( $self->detect_site_init() ) ) {
    my $ec = qq{ -l "site-start" };
    $self->append_to_ec_lib_loader( $ec );
  }

  if ($load_emacs_init) {
    my $dot_emacs = $self->find_dot_emacs;
    if ( $dot_emacs ) {
      my $ec = qq{ -l "$dot_emacs" };
      $self->append_to_ec_lib_loader( $ec );
    }
  }

  if ( ($load_default_init) && ($self->detect_lib( 'default' )) ) {
    my $ec = qq{ -l "default" };
    $self->append_to_ec_lib_loader( $ec );
  }

  $ec_lib_loader = $self->ec_lib_loader;
  return $ec_lib_loader;
}

=item guess_type_from_name

Given the name of an emacs library, examine it to see
if it looks like a file system path, or an emacs
feature name (sans path or extension)

=cut

sub guess_type_from_name {
  my $self = shift;
  my $name = shift;

  my $path_found = ( $name =~ m{/}xms );
  my $ext_found =  ( $name =~ m{\.el[c]?$}xms );

  my $type;
  if (($path_found) && ($ext_found)) {
    $type = 'file';
  } elsif ($path_found) {
    $type = 'file';
  } elsif ($ext_found) {
    $type = 'file';
  } else {
    $type = 'lib';
  }
  return $type;
}

=back

=head2 generation of emacs command strings to load libraries

A set of four routines to generate a string that can be included in
an emacs command line invocation to load the given library.  The
methods here are named according to the pattern:

  "genec_loader_$type_$priority"

All of these methods return the generated string, but also append it
to the L</ec_lib_loader> attribute,

=over

=item genec_loader_lib_needed

=cut

sub genec_loader_lib_needed {
  my $self = shift;
  my $name = shift;

  unless( defined( $name) ) {
    return;
  }

  my $ec = qq{ -l "$name" };  ### TODO names are not allowed to contain double-quotes then? (fix)

  $self->append_to_ec_lib_loader( $ec );
  return $ec;
}

=item genec_loader_file_needed

=cut

sub genec_loader_file_needed {
  my $self = shift;
  my $name = shift;

  unless ( -e $name ) {
    croak "Could not find required elisp library file: $name.";
  }
  my $elisp =
    $self->quote_elisp(
                       $self->elisp_to_load_file( $name )
                      );
  my $ec = qq{ --eval "$elisp" };
  $self->append_to_ec_lib_loader( $ec );
  return $ec;
}

=item genec_loader_lib_requested

=cut

sub genec_loader_lib_requested {
  my $self = shift;
  my $name = shift;

  unless ( $self->detect_lib( $name ) ) {
    return;
  }

  my $ec = qq{ -l "$name" };
  $self->append_to_ec_lib_loader( $ec );
  return $ec;
}

=item genec_loader_file_requested

=cut

sub genec_loader_file_requested {
  my $self = shift;
  my $name = shift;

  unless( -e $name ) {
    return;
  }

  my $elisp =
    $self->quote_elisp(
                       $self->elisp_to_load_file( $name )
                      );

  my $ec = qq{ --eval "$elisp" };
  $self->append_to_ec_lib_loader( $ec );
  return $ec;
}

=back

=head2 Emacs probes

Methods that return information about the emacs installation.

=over

=item probe_emacs_version

Returns the version of the emacs program stored on your system.
This is called during the object initialization phase.

It checks the emacs specified in the object's emacs_path
(which defaults to the simple command "emacs", sans any path),
and returns the version.

As a side-effect, it sets a number of object attributes with
details about the emacs version:

  emacs_version
  emacs_major_version
  emacs_type

=cut

sub probe_emacs_version {
  my $self = shift;

  my $emacs = $self->emacs_path;

  my $cmd = "$emacs --version";
  my $text = qx{ $cmd };

  # $self->debug( $text, "\n" );

  my $version = $self->parse_emacs_version_string( $text );

  return $version;
}


=item parse_emacs_version_string

The emacs version string returned from running "emacs --version"
is parsed by this routine, which picks out the version
numbers and so on and saves them as object data.

See probe_emacs_version (which uses this internally).

=cut

# Note, a Gnu emacs version string has a first line like so:
#   "GNU Emacs 22.1.1",
# followed by several other lines.
#
# For xemacs, the last line is important, though it's preceeded by
# various messages about for libraries loaded.

# Typical version lines.
#   GNU Emacs 22.1.1
#   GNU Emacs 22.1.92.1
#   GNU Emacs 23.0.0.1
#   GNU Emacs 21.4.1
#   XEmacs 21.4 (patch 18) "Social Property" [Lucid] (amd64-debian-linux, Mule) of Wed Dec 21 2005 on yellow

sub parse_emacs_version_string {
  my $self           = shift;
  my $version_mess   = shift;

  my ($emacs_type, $version);
  # TODO presumption is versions are digits only (\d). Ever have letters, e.g. 'b'?
  if (      $version_mess =~ m{^ ( GNU \s+ Emacs ) \s+ ( [\d.]* ) }xms ) {
    $emacs_type = $1;
    $version    = $2;
  } elsif ( $version_mess =~ m{ ^( XEmacs )        \s+ ( [\d.]* ) }xms ) {
    $emacs_type = $1;
    $version    = $2;
  } else {
    $emacs_type ="not so gnu, not xemacs either";
  }
  $self->debug( "version: $version\n" );

  $self->set_emacs_type( $emacs_type );
  $self->set_emacs_version( $version );

  my (@v) = split /\./, $version;

  my $major_version = $v[0];
  $self->set_emacs_major_version( $major_version );
  $self->debug( "major_version: $major_version\n" );

  return $version;
}

=back

=head2 internal utilities (used by initialization code)

=over

=item elisp_to_load_file

Given the location of an emacs lisp file, generate the elisp
that ensures the library will be available and loaded.

=cut

sub elisp_to_load_file {
  my $self       = shift;
  my $elisp_file = shift;

  my $path = dirname( $elisp_file );

  my $elisp = qq{
   (progn
    (add-to-list 'load-path
      (expand-file-name "$path/"))
    (load-file "$elisp_file"))
  };
}

=item find_dot_emacs

Looks for one of the variants of the user's emacs init file
(e.g. "~/.emacs") in the same order that emacs would, and
returns the first one found.

Note: this relies on the environment variable $HOME.  (This
can be changed first to cause this to look for an emacs init
in some arbitrary location, e.g. for testing purposes.)

This code does not issue a warning if the elc is stale compared to
the el, that's left up to emacs.

=cut

sub find_dot_emacs {
  my $self = shift;
  my @dot_emacs_candidates = (
                   "$HOME/.emacs",
                   "$HOME/.emacs.elc",
                   "$HOME/.emacs.el",
                   "$HOME/.emacs.d/init.elc",
                   "$HOME/.emacs.d/init.el",
                  );

  my $dot_emacs =  first { -e $_ } @dot_emacs_candidates;
  return $dot_emacs;
}

=item detect_site_init

Looks for the "site-start.el" file in the raw load-path
without loading the regular emacs init file (e.g. ~/.emacs).

Emacs itself normally loads this file before it loads
anything else, so this method replicates that behavior.

Returns the library name ('site-start') if found, undef if not.

=cut

sub detect_site_init {
  my $self = shift;
  my $subname = ( caller(0) )[3];

  my $emacs = $self->emacs_path;
  my $before_hook = $self->before_hook;

  my $lib_name = 'site-start';
  my $emacs_cmd = qq{ $emacs --batch $before_hook -l $lib_name 2>&1 };

  $self->debug("$subname emacs_cmd:\n $emacs_cmd\n");

  my $return = qx{ $emacs_cmd };

  $self->debug("$subname return:\n $return\n");

  my $last_line = ( split /\n/, $return )[-1] || '';

  if ( $last_line =~ m{^\s*Cannot open load file:} ) {
    return;
  } else {
    return $lib_name;
  }
}

=item detect_lib

Looks for the given elisp library in the load-path after
trying to load the given list of context_libs (that includes .emacs
as appropriate, and this method uses the requested_load_files as
context, as well).

Returns $lib if found, undef if not.

Example usage:

   if ( $self->detect_lib("dired") ) {
       print "As expected, dired.el is installed.";
   }

   my @good_libs = grep { defined($_) } map{ $self->detect_lib($_) } @candidate_libs;

=cut

sub detect_lib {
  my $self         = shift;
  my $lib          = shift;

  return unless $lib;

  my $emacs = $self->emacs_path;
  my $before_hook = $self->before_hook;
  my $ec_head = qq{ $emacs --batch $before_hook };
  # emacs_cmd string to load existing, presumably vetted, libs
  my $ec_lib_loader = $self->ec_lib_loader;

  my $ec_tail = qq{ 2>&1 };

  my $emacs_cmd = qq{ $ec_head $ec_lib_loader -l $lib $ec_tail};
  my $return = qx{ $emacs_cmd };
  my $last_line = ( split /\n/, $return )[-1];

  if ( defined( $last_line ) &&
       $last_line =~ m{^\s*Cannot open load file:} ) {
    return;
  } else {
    return $lib;
  }
}

=back

=head2 routines in use by Emacs::Run::ExtractDocs

=over

=item elisp_file_from_library_name_if_in_loadpath

Identifies the file associated with a given elisp library name by
shelling out to emacs in batch mode.

=cut

sub elisp_file_from_library_name_if_in_loadpath {
  my $self    = shift;
  my $library = shift;
  my $subname = (caller(0))[3];

  my $elisp = qq{
     (progn
       (setq codefile (locate-library "$library"))
       (message codefile))
  };

  my $return = $self->eval_elisp( $elisp );

  my $last_line = ( split /\n/, $return )[-1];

  my $file;
  if ( ($last_line) && (-e $last_line) ) {
    $self->debug( "$subname: $last_line is associated with $library\n" );
    $file = $last_line;
  } else {
    $self->debug( "$subname: no file name found for lib: $library\n" );
    $file = undef;
  }

  return $file;
}

=item generate_elisp_to_load_library

Generates elisp code that will instruct emacs to load the given
library.  It also makes sure it's location is in the load-path, which
is not precisely the same thing: See L</loaded vs. in load-path>.

Takes one argument, which can either be the name of the library, or
the name of the file, as distinguished by the presence of a ".el"
extension on a file name.  Also, the file name will usually have a
path included, but the library name can not.

=cut

sub generate_elisp_to_load_library {
  my $self = shift;
  my $arg  = shift;

  my ($elisp, $elisp_file);
  if ($arg =~ m{\.el$}){
    $elisp_file = $arg;
    $elisp = $self->elisp_to_load_file( $elisp_file );
  } else {

    $elisp_file = $self->elisp_file_from_library_name_if_in_loadpath( $arg );

    unless( $elisp_file ) {
      croak "Could not determine the file for the named library: $arg";
    }

    $elisp = $self->elisp_to_load_file( $elisp_file );
  }
  return $elisp;
}


=back

=head2 basic setters and getters

The naming convention in use here is that setters begin with
"set_", but getters have *no* prefix: the most commonly used case
deserves the simplest syntax (and mutators are deprecated).

These accessors exist for all of the object attributes (documented
above) irrespective of whether they're expected to be externally useful.

=head2 special accessors

=over

=item append_to_ec_lib_loader

Non-standard setter that appends the given string to the
the L</elisp_to_load_file> attribute.

=cut

sub append_to_ec_lib_loader {
  my $self = shift;
  my $append_string = shift;

  my $ec_lib_loader = $self->{ ec_lib_loader } || '';
  $ec_lib_loader .= $append_string;

  $self->{ ec_lib_loader } = $ec_lib_loader;

  return $ec_lib_loader;
}


=item append_to_before_hook

Non-standard setter that appends the given string to the
the L</before_hook> attribute.

Under some circumstances, the code here uses the L</before_hook>
(for -Q and --no-splash), so using a setter is mildly dangerous.
Typically it's better to just append to the L</before_hook>.

=cut

sub append_to_before_hook {
  my $self = shift;
  my $append_string = shift;

  my $before_hook = $self->{ before_hook } || '';
  $before_hook .= $append_string;

  $self->{ before_hook } = $before_hook;

  return $before_hook;
}

=back

=head2 accessors that effect the L</ec_lib_loader> attribute

If either lib_data or emacs_libs is re-set, this must
trigger another run of L</set_up_ec_lib_loader> to keep
the L</ec_lib_loader> string up-to-date.

=over

=item set_lib_data

Setter for lib_data.

=cut

sub set_lib_data {
  my $self = shift;
  my $lib_data = shift;
  $self->{ lib_data } = $lib_data;
  $self->set_up_ec_lib_loader;
  return $lib_data;
}

=item set_emacs_libs

Setter for emacs_libs.

=cut

sub set_emacs_libs {
  my $self = shift;
  my $emacs_libs = shift;
  $self->{ emacs_libs } = $emacs_libs;
  $self->set_up_ec_lib_loader;
  return $emacs_libs;
}

=back

=head2  automatic generation of standard accessors

=over

=item AUTOLOAD

=cut

sub AUTOLOAD {
  return if $AUTOLOAD =~ /DESTROY$/;  # skip calls to DESTROY ()

  my ($name) = $AUTOLOAD =~ /([^:]+)$/; # extract method name
  (my $field = $name) =~ s/^set_//;

  # check that this is a valid accessor call
  croak("Unknown method '$AUTOLOAD' called")
    unless defined( $ATTRIBUTES{ $field } );

  { no strict 'refs';

    # create the setter and getter and install them in the symbol table

    if ( $name =~ /^set_/ ) {

      *$name = sub {
        my $self = shift;
        $self->{ $field } = shift;
        return $self->{ $field };
      };

      goto &$name;              # jump to the new method.
    } elsif ( $name =~ /^get_/ ) {
      carp("Apparent attempt at using a getter with unneeded 'get_' prefix.");
    }

    *$name = sub {
      my $self = shift;
      return $self->{ $field };
    };

    goto &$name;                # jump to the new method.
  }
}




1;
#========
# end of code

=back

=head2 MOTIVATION

Periodically, I get interested in the strange world of
running emacs code from perl.  There's a mildly obscure
feature of emacs command line invocations called "--batch"
that lets one use it non-interactively, and a number of other
command-line options to load files of elisp code or run
snippets of code from the command-line.

You might think that there isn't much use for this trick,
but I can think of many reasons:

=over

=item to probe your emacs set-up from perl, e.g. for automated installation of elisp using perl tools

=item to test elisp code using a perl test harness.

=item to use tools written in elisp that you don't want to rewrite in perl (e.g. extract-docstrings.el)

=back

Emacs command line invocation is a little language all of it's own,
with just enough twists and turns to it that I've felt the need to
write perl routines to help drive the process.

=head2 emacs invocation vs Emacs::Run

By default an "emacs --batch" run suppresses most of the usual init
files (but does load the essentially deprecated "site-start.pl",
presumably for backwards compatibility).  Emacs::Run has the opposite
bias: here we try to load all three of the types of init files, if
they're available, though each one of these can be shut-off
individually if so desired.  This is because one of the main things
this code is for is to let perl find out about things such as the
user's emacs load-path settings (and in any case, the performance hit
of loading these files is no-longer such a big deal).

=head1 internal documentation (how the code works, etc).

=head2 internal attributes

Object attributes intended largely for internal use.  The client
programmer has access to these, but is not expected to need it.
Note: the common "leading underscore" naming convention is not used here.

=over

=item  ec_lib_loader

A fragment of an emacs command line invocation to load emacs libraries.
Different attributes exist to specify emacs libraries to be loaded:
as these are processed, the ec_lib_loader string gradually accumulates
code needed to load them (so that when need be, the process can use
the intermediate value of the ec_lib_loader to get the benefit of
the previously processed library specifications).

The primary reason for this approach is that each library loaded
has the potential to modify the emacs load-path, which may be
key for the success of later load attempts.

The process of probing for each library in one of the "requested"
lists has to be done in the context of all libraries that have been
previously found.  Without some place to store intermediate results
in some form, this process might need to be programmed as one large
monolithic routine.

=back

=head2 strategies in shelling out

Perl has a good feature for running a shell command and capturing
the output: qx{} (aka back-quotes), and it's easy enough to append
"2>&1" to a shell command when you'd like to see the STDERR messages
intermixed with the STDOUT. However, there does not appear to be any
simple method of distinguishing between the messages from STDERR and
STDOUT later; so, this project almost always works with them intermixed.

The method L</eval_elisp> intermixes, though there's an alternate form
L</eval_elisp_skip_err> that only returns STDOUT.

=head1 NOTES

=head2 loaded vs. in load-path

The emacs variable "load-path" behaves much like the shell's $PATH
(or perl's @INC): if you try to load a library called "dired", emacs
searches through the load-path in sequence, looking for an appropriately
named file (e.g. "dired.el"), it then evaluates it's contents, and
the objects defined in the file become available for use.  It is also possible
to load a file by telling emacs the path and filename, and that works
whether or not it is located in the load-path.

There I<is> at least a slight difference between the two,
however.  For example, the "extract-docstrings.el" package
contains code like this, that will break in the later case:

  (setq codefile (locate-library library))

So some of the routines here (notably L</elisp_to_load_file>)
generate elisp with an extra feature that adds the location of the file
to the load-path as well as just loading it.

=head2 interactive vs. non-interactive elisp init

Emacs::Run tries to use the user's normal emacs init process even
though it runs non-interactively.  Unfortunately, it's possible that
the init files may need to be cleaned up in order to run non-interactively.
In my case I found that I needed to check the "x-no-window-manager" variable
and selectively disable some code that sets X fonts for me:

  ;; We must do this check to allow "emacs --batch -l .emacs" to work
  (unless (eq x-no-window-manager nil)
    (zoom-set-font "-Misc-Fixed-Bold-R-Normal--15-140-75-75-C-90-ISO8859-1"))

=head1 TODO

=over

=item *

Eliminate unixisms, if possible.  A known one: there's a heuristic
that spots file paths by looking for "/".  Use File::Spec.

=item *

Modify the eval_function method to allow for arguments to be
passed through to the function.

=item *

I suspect some quoting issues still lurk e.g.  a library
filename containing a double-quote will probably crash things.

=item *

Add a method to match a emacs regexp against a string. See:
L<http://obsidianrook.com/devnotes/talks/test_everything/bin/1-test_emacs_regexps.t.html>

      (goto-char (point-min))
      (re-search-forward "$elisp_pattern")
      (setq first_capture (match-string 1))

=item *

In L</run_elisp_on_file>, add support for skipping to a line number
after opening a file

=item *

Provide additional methods such as L</eval_elisp_skip_err> to allow
the client coder more choice about whether STDOUT and STDERR will be
returned intermixed.  Possibly: provide a facility to send STDERR to
a log file, rather than capture it

=back

=head1 SEE ALSO

L<Emacs::Run::ExtractDocs>

Emacs Documentation: Command Line Arguments for Emacs Invocation
L<http://www.gnu.org/software/emacs/manual/html_node/emacs/Emacs-Invocation.html>

A lightning talk about (among other things) using perl to test
emacs code: "Using perl to test non-perl code":

L<http://obsidianrook.com/devnotes/talks/test_everything/index.html>


=head1 AUTHOR

Joseph Brenner, E<lt>doom@kzsu.stanford.eduE<gt>,
07 Mar 2008

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 by Joseph Brenner

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.2 or,
at your option, any later version of Perl 5 you may have available.

=head1 BUGS & LIMITATIONS

When the client coder specifies that a library is "needed", failure
occurs relatively late if it's not available: it does not happen
during object instantiation, but waits until an attempted run with
the object (e.g. "$er->eval_elisp".

=cut