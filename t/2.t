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

foreach $iList ( 0 .. scalar @list - 1 ) {
    my $place = $list[$iList];
    get_dirs ( { save_format => $fmt }, @$place );

    foreach ( 1 .. scalar @$place - 1 ) {
        my $test_fname = sprintf "t/test_%d_%d.html", $iList, $_;
        my $fname = sprintf $fmt, $_;

        my $test_file = read_file ( $test_fname );
        my $comp_file = read_file ( $fname );

        is ( $test_file, $comp_file );
        unlink $fname;
    }
}

sub read_file { 
    my ( $fname ) = @_;
    my $content;

    open my $fh, $fname or die "can't open $fname: $!\n";
    while ( <fh> ) {
        $content .= $_
            if /\w{3} \w{3} \d{2} \d{2}:\d{2}:\d{2} \w{3} \d{4}/;
    }
    close $fh;

    return $content;
}
