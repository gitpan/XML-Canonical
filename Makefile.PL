use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'		=> 'XML::Canonical',
    'VERSION_FROM'	=> 'lib/XML/Canonical.pm', # finds $VERSION
    'PREREQ_PM'		=> {XML::LibXML => 1.30}, # e.g., Module::Name => 1.1
);
