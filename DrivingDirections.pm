
package WWW::Yahoo::DrivingDirections;

use strict;
use warnings;

require Exporter;

our @EXPORT_OK = qw/get_dirs get_directions/;
our @ISA = qw/Exporter/;
our $VERSION = '0.07';

use Carp;
use List::Util qw/shuffle sum/;
use Regexp::Common;
use WWW::Mechanize;

sub new {
    my $proto = shift;
    my $class = ref ( $proto ) || $proto;

    # Create object:
    #
    my $self = bless {
        total_dist  => 0.0,
        roundtrip   => 0,
        stops       => [],
        proc_stops  => [],
        cStops      => undef,
        return_html => 0,
        save_html   => 1,
        save_format => 'trip_leg_%d.html',
        mech        => WWW::Mechanize->new (),
    }, $class;

    # Read arguments: put hash arguments into the object's hash,
    #   put scalars into the stops array.
    #
    foreach my $arg ( @_ ) {
        if ( 'HASH' eq ref $arg ) {
            foreach ( keys %$arg ) {
                $self->{$_} = $arg->{$_} if exists $self->{$_};
            }
        }
        elsif ( '' eq ref $arg ) {
            $self->add_stops ( $arg );
        }
        else {
            carp "Ignoring argument $arg: not a hashref or scalar";
        }
    }
    return $self;
}

sub add_stops {
    my $self = shift () or die "no self in add_stops";
    push @{$self->{stops}}, @_;
    return $self->stops_number ();
}

sub list_stops {
    my $self = shift () or die "no self in list_stops";
    return join ( "\n", @{$self->{stops}} ), "\n";
}

sub shuffle_stops {
    my $self = shift () or die "no self in shuffle_stops";
    @{$self->{stops}} = shuffle ( @{$self->{stops}} );
}

sub clear_stops {
    my $self = shift () or die "no self in clear_stops";
    $self->{stops} = [];
}

sub total_distance {
    my $self = shift () or die "no self in total_distance";
    return $self->{total_dist};
}

sub number_of_stops {
    my $self = shift () or die "no self in number_of_stops";
    return $self->stops_number ();
}
sub stops_number {
    my $self = shift () or die "no self in stops_number";
    $self->{cStops} = scalar @{$self->{stops}};
    return $self->{cStops};
}

sub roundtrip {
    my $self = shift () or die "no self in roundtrip";
    $self->{roundtrip} = shift () if scalar @_ > 0;
    return $self->{roundtrip};
}

sub get_maps {
    my $self = shift () or die "no self in get_maps";

    $self->_process_stops ();

    croak "Only $self->{cStops} addresses entered. Need 2 or more."
        if $self->{cStops} < 2;

    # Get the maps.yahoo.com driving directions page for each valid trip leg:
    #
    my $end = $self->{cStops} - ( $self->{roundtrip} ? 1 : 2 );
    foreach ( 0 .. $end ) {
        my $leg = $self->get_trip_leg_page ( $_ );
        my $bGood = $leg =~ m/distance:/i &&
                    $leg =~ m/approximate travel time:/i;

        if ( ! $bGood ) {
            carp "Skipping leg $_: $self->{stops}[$_] to $self->{stops}[$_+1]" .
                 " trip: maps.yahoo.com cannot find";
            next;
        }
        push @{$self->{trip_legs}}, $leg;
    }

    # Get total distance:
    #
    $self->{total_dist} = sum ( map { leg_dist( $_ ) } @{$self->{trip_legs}} );

    # Warn if the return_html and save_html params make get_maps a no-op:
    #
    carp "Both return_html and save_html are false"
        if !$self->{return_html} && !$self->{save_html};

    # Write the trip legs to their output html files, if requested:
    #
    if ( $self->{save_html} ) {
        foreach ( 0 .. scalar @{$self->{trip_legs}} - 1 ) {
            my $fname = sprintf "$self->{save_format}", $_+1;
            open ( my $out_fh, '>', $fname )
                or die "Can't open file '$fname': $!";
            print $out_fh $self->{trip_legs}[$_];
            close $out_fh 
                or carp "problem closing '$fname': $!";
        }
    }
    return $self->{trip_legs}
        if $self->{return_html};
}

sub _process_stops {
    my $self = shift () or die "no self in _process_stops";

    # Clean the proc_stops array:
    # 
    $self->{proc_stops} = [];

    foreach ( @{$self->{stops}} ) {

        # Get rid of multiple sequencial commas
        #
        s/,+/,/g;

        # Count commas, split the line into an anonymous array w/ $count elems
        #
        my $count = () = m/,/g;

        # If $count is 2, the address is assumed to be of the form "123 fake
        #   st, anytown, MO".  If $count is 1, the address is assumed to be of
        #   the form "anytown, MO".  If $count is 0, the address is assumed to
        #   be either a three-letter airport code or a valid zip code.
        #
        # After the form of the address is determined, it is parsed on commas
        #   into an array, which is then pushed into the $self->{proc_stops}
        #   array.
        #
        my @addr = ();
        if ( 2 == $count ) {
            @addr = split /,/, $_, 2;
        }
        elsif ( 1 == $count ) {
            @addr = ( "", $_ );
        }
        elsif ( 0 == $count ) {
            @addr = /^$RE{zip}{US}$/ ? ( "", $_ )
                  : /^\w{3}$/        ? ( $_, "" )
                  : bad_address ( $_ );
        }
        else {
            bad_address ( $_ );
        }

        # Clean up the spaces:
        #
        do { s/^\s+|\s+$//g; s/\s+/ /g } foreach @addr;

        # Push a ref to the properly-formatted address onto the proc_stops
        #   array  (get_maps works on the proc_stops array).
        #
        push @{$self->{proc_stops}}, [ @addr ];
    }
}

sub get_trip_leg_page {
    my ( $self, $num ) = @_;

    my $idx1 =        $num   % $self->{cStops};
    my $idx2 = ( $idx1 + 1 ) % $self->{cStops};

    $self->{mech}->get ( 'http://maps.yahoo.com/dd' );
    die "Page get failure: $!" 
        if not $self->{mech}->success ();

    my $resp = $self->{mech}->submit_form (
        form_name => 'dd',
        fields => {
            addr  => $self->{proc_stops}[$idx1][0],
            csz   => $self->{proc_stops}[$idx1][1],
            taddr => $self->{proc_stops}[$idx2][0],
            tcsz  => $self->{proc_stops}[$idx2][1],
        },
    );
    croak "Form submission failure: $!" 
        if not $self->{mech}->success ();
    return $resp->{_content}
}

# Functions.
#
sub bad_address {
    my $bad = shift () 
        or croak "no address in WWW::Yahoo::DrivingDirections::bad_address";

    croak join "\n\t",
        "Error: invalid entry '$bad'.  Valid addresses are in these formats:",
        "'123 fake st, anytown, az' (street adddress, city, state)",
        "'123 fake st, anytown, az 87530' (street adddress, city, state zip)",
        "'Boston, ma' (city, state)",
        "'Boston, ma 02138' (city, state)",
        "'90210' (zip only)",
        "'LAX' (three letter airport code)\n";
}

sub leg_dist {
    my $trip_leg = shift () or die "no trip_leg in leg_dist\n";
    my ( $leg_dist ) = $trip_leg =~ m/Distance:.*?([.\d]+) miles/s;
    $leg_dist = 0.0 if not defined $leg_dist;
    return $leg_dist;
}

sub get_directions {
    return get_dirs ( @_ );
}
sub get_dirs {
    my $yd = WWW::Yahoo::DrivingDirections->new ( @_ );
    $yd->get_maps();
    return $yd->total_distance ();
}

1;

__END__

=head1 NAME

WWW::Yahoo::DrivingDirections - Generate driving directions for multiple-stop
trips in the United States, courtesy of maps.yahoo.com.

=head1 ABSTRACT

Object-oriented interface to the maps.yahoo.com driving directions.

=head1 SYNOPSIS

    use WWW::Yahoo::DrivingDirections;
    my $yd = WWW::Yahoo::DrivingDirections->new ();
    $yd->add_stops ( @ARGV ); 
    $yd->get_maps();

or

    use WWW::Yahoo::DrivingDirections;
    my $yd = WWW::Yahoo::DrivingDirections->new (
                  {
                      roundtrip   => 1,
                      return_html => 1,
                      save_html   => 0,
                      save_format => 'output_%d.html',
                  },
                  'atlanta, ga',
                  '123 fake st, boston, ma',
                  '0 church st, cambridge, ma',
                  'LAX',
              );
    $yd->add_stops ( 'paris, tx', '1 main st, springfield, IL' ); 
    $yd->roundtrip ( 1 );
    $html_array_ref = $yd->get_maps();

=head1 DESCRIPTION

WWW::Yahoo::DrivingDirections provides a simple means of generating driving
directions for trips with more stops than a start and a finish.  Driving from
LAX airport to 1 Main St, Portland, OR to Denver, CO?  Just do this:

    use WWW::Yahoo::DrivingDirections;
    my $yd = WWW::Yahoo::DrivingDirections->new (
                 'LAX', '1 Main St, Portland, OR', 'Denver, CO'
             );
    $yd->get_maps();

and the directions will be saved in trip_leg_1.html and trip_leg_2.html.

=head2 Methods

=over 4

=item B<new>

Creates a new WWW::Yahoo::DrivingDirections instance.  A list of string
arguments containing stops will be added to the object's list of destinations.
A hash reference argument to this function with some or all of the following
keys is allowed:

=over 8

=item I<roundtrip>

A boolean.  If true, a route from the last given stop to the first will be
generated.  The default is false.

=item I<return_html>

A boolean.  If true, the get_maps method returns a reference to an array of 
the the html driving direction pages.  If false, the get_maps method returns
nothing.  The default is false.

=item I<save_html>

A boolean.  If true, the get_maps method writes the html driving direction
pages to files with names defined by save_format parameter.  The default is 
true.  Setting both return_html and save_html to 0 makes get_maps a null-op, 
and is not reccomended.

=item I<save_format>

A printf format string defining the filenames that the driving directions
are saved to if save_html is true.  The default is 'trip_leg_%d.html'.  There
must be one %d one %s in the string to take the trip leg number.  Example:  if 
there are two trip legs, trip_leg_1.html and trip_leg_2.html will be the output
files.

=item I<mech>

The WWW::Mechanize object that interacts with maps.yahoo.com.  A user-defined
WWW::Mechanize object can be supplied.

=back

=item B<add_stops>

Add stops to the object's list of driving destinations.  The are pushed onto
the list.  Returns the current number of stops.

Allowed address formats are the following:

    "123 fake st, anytown, az" (street adddress, city, state)
    "123 fake st, anytown, az 87530" (street adddress, city, state zipcode)
    "Boston, ma" (city, state)
    "Boston, ma 02138" (city, state)
    "90210" (zipcode only)
    "LAX" (three letter airport code)

The addresses are parsed on commas; do not add a comma between state and zipcode.

=item B<list_stops>

Returns a return-delimited string of the driving stops that have been entered.

=item B<shuffle_stops>

Randomizes the order of the stops.

=item B<clear_stops>

Clears the list of stops (presumably in order to do another trip). 

=item B<total_distance>

Returns the summed distance of all the trip legs.  Returns 0 if run before
get_maps.  

=item B<number_of_stops>

Returns the current number of stops.

=item B<stops_number>

Identical to number_of_stops.

=item B<roundtrip>

Sets the roundtrip flag to the argument.  If the roundtrip flag is true, a
trip leg between the last destination and the first destination will be
created.  Returns the current value of the roundtrip flag.

=item B<get_maps>

Generates the driving direction pages.   The pages are either written to files
or returned as a reference to an array of the html pages, or neither, or both,
depending on the settings of the return_html and save_html flags.

=back

=head2 Functions

=over 4

=item B<get_dirs>

A functional interface to the module.  All arguments are passed to
WWW::Yahoo::DrivingDirections::new, and get_maps is run on the resultant
object.

=over 4

=item B<get_directions>

Identical to get_dirs.

=back

=head1 EXPORT

The (identical) functions get_dirs and get_directions are exported on request.

=head1 AUTHOR

Kester Allen, kester@gmail.com

=head1 VERSION

0.04

=head1 SEE ALSO

WWW::Mechanize, maps.yahoo.com

=head1 AUTHOR

Kester Allen, kester@gmail.com

=head1 COPYRIGHT AND LICENSE

Copyright 2004 by Kester Allen

This module is free software; you can redistribute it and/or modify it under
the same terms as Perl itself. 

=cut
