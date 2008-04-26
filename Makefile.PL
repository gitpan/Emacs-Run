use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Emacs::Run',
    VERSION_FROM      => 'lib/Emacs/Run.pm', # finds $VERSION
    PREREQ_PM         => {
                          Class::Base          => 0.03,
                          IPC::Capture         => 0,
#                          IPC::Cmd             => 0,
                          Data::Dumper         => 0,
                          File::Spec           => 0,
                          File::Basename       => 0,
                          File::Copy           => 0,
                          Hash::Util           => 0,
                          List::MoreUtils      => 0,
                          List::Util           => 0,
                          Test::Differences    => 0,
                          Test::More           => 0,
                          lib                  => 0,
                          base                 => 0,
                          strict               => 0,
                          warnings             => 0,
                         },
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Emacs/Run.pm', # retrieve abstract from module
       AUTHOR         => 'Joseph Brenner <doom@>') : ()),
);
