use 5.008;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'          => 'WWW::Yahoo::DrivingDirections',
    'VERSION_FROM'  => 'DrivingDirections.pm', # finds $VERSION
    'PREREQ_PM'	    => { 'Regexp::Common' => 0, 
                         'WWW::Mechanize' => 0, 
                         'List::Util'     => 0, }, 
    ($] >= 5.005 ?    ## Add these new keywords supported since 5.005
      (AUTHOR     => 'Kester Allen <kester@gmail.com>') : ()),
);
