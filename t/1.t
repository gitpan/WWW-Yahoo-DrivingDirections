# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl 1.t'

#########################

use Test::More tests => 7;
BEGIN { use_ok('WWW::Yahoo::DrivingDirections') };

#########################

use Data::Dumper;
use WWW::Yahoo::DrivingDirections qw/ get_dirs /;

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $fmt ='c_%d.html';
my @list = (
    ['01002', '98020', 'LAX', 'atlanta, ga'],
    ['35 kinnaird st, cambridge, ma', '1600 pennsylvania ave, washington, dc'],
    [ { roundtrip => 1 }, 'boston, ma', 'oakland, ca'],
);

foreach my $place ( @list ) {
    get_dirs ( { save_format => $fmt }, @$place );

    foreach ( 1 .. scalar @$place - 1 ) {
        my $fname = sprintf $fmt, $_;
        ok ( -f $fname );
        unlink $fname;
    }
}
