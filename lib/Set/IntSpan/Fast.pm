package Set::IntSpan::Fast;

use warnings;
use strict;
use Carp;
use Class::Std;
use Data::Types qw(is_int);
use List::Util qw(min max);

use version; our $VERSION = qv('0.0.2');

use constant {
    POSITIVE_INFINITY   =>  2 ** 31 - 2,
    NEGATIVE_INFINITY   => -2 ** 31 + 1
};

my %edges : ATTR;

sub BUILD {
    my ($self, $id, $args) = @_;
    
    $edges{$id} = [ ];
}

sub invert {
    my $self  = shift;
    my $id    = ident($self);
    
    if ($self->is_empty()) {
        # Empty set
        $edges{$id} = [ NEGATIVE_INFINITY, POSITIVE_INFINITY ];
    } else {
        my $edges = $edges{$id};
        # Either add or remove infinity from each end. The net
        # effect is always an even number of additions and deletions
        if ($edges->[0] == NEGATIVE_INFINITY) {
            shift @{$edges};
        } else {
            unshift @{$edges}, NEGATIVE_INFINITY;
        }
        
        if ($edges->[-1] == POSITIVE_INFINITY) {
            pop @{$edges};
        } else {
            push @{$edges}, POSITIVE_INFINITY;
        }
    }
}

sub copy {
    my $self  = shift;
    my $id    = ident($self);
    my $copy  = Set::IntSpan::Fast->new();
    my $cid   = ident($copy);
    $edges{$cid} = [ @{$edges{$id}} ];
    return $copy;
}

sub _list_to_ranges {
    my @list   = sort { $a <=> $b } @_;
    my @ranges = ( );
    my $count  = scalar(@list);
    my $pos    = 0;
    while ($pos < $count) {
        my $end = $pos + 1;
        $end++ while $end < $count && $list[$end] <= $list[$end-1] + 1;
        push @ranges, ( $list[$pos], $list[$end-1] );
        $pos = $end;
    }
    
    return @ranges;
}

sub add {
    my $self = shift;
    my $id   = ident($self);
    $self->add_range(_list_to_ranges(@_));
}

sub remove {
    my $self = shift;
    my $id   = ident($self);
    $self->remove_range(_list_to_ranges(@_));
}

sub _iterate_ranges {
    my $cb = pop @_;

    my $count = scalar(@_);
    
    croak "Range list must have an even number of elements"
        if ($count % 2) != 0;

    for (my $p = 0; $p < $count; $p += 2) {
        my ($from, $to) = ( $_[$p], $_[$p+1] );
        croak "Range limits must be integers"
            unless is_int($from) && is_int($to);
        croak "Range limits must be in ascending order"
            unless $from <= $to;
        croak "Value out of range"
            unless $from >= NEGATIVE_INFINITY && $to <= POSITIVE_INFINITY;
 
        # Internally we store inclusive/exclusive ranges to
        # simplify comparisons, hence '$to + 1'
        $cb->($from, $to + 1);
    }
}

# Return the index of the first element >= the supplied value. If the
# supplied value is larger than any element in the list the returned
# value will be equal to the size of the list.
sub _find_pos {
    my $edges = shift;
    my $val   = shift;
    my $low   = shift || 0;

    my $count = scalar(@$edges);
    my $high  = $count-1;

    # TODO: Optimise the case where the value is at one end or other of
    # the range
    my $mid = $low;
    while ($low <= $high) {
        $mid = int(($low + $high) / 2);
        if ($val < $edges->[$mid]) {
            $high = $mid - 1;
        } elsif ($val > $edges->[$mid]) {
            $low  = $mid + 1;
        } else {
            return $mid;
        }
    }

    # Sometimes we need to correct because $mid is always rounded down.
    $mid++ if $mid < $count && $edges->[$mid] < $val;
    
    return $mid;
}

sub add_range {
    my $self  = shift;
    my $id    = ident($self);
    my $edges = $edges{$id};

    _iterate_ranges(@_, sub {
        my ($from, $to) = @_;

        my $fpos = _find_pos($edges, $from);
        my $tpos = _find_pos($edges, $to + 1, $fpos);

        $from = $edges->[--$fpos] if ($fpos & 1);
        $to   = $edges->[$tpos++] if ($tpos & 1);

        splice @$edges, $fpos, $tpos - $fpos, ( $from, $to );
    });
}

sub remove_range {
    my $self = shift;

    $self->invert();
    $self->add_range(@_);
    $self->invert();
}

sub merge {
    my $self = shift;

    for my $other (@_) {
        my $iter = $other->iterate_runs();
        while (my ($from, $to) = $iter->()) {
            $self->add_range($from, $to);
        }
    }
}

sub is_empty {
    my $self = shift;
    my $id   = ident($self);
    
    return @{$edges{$id}} == 0;
}

sub contains_all {
    my $self  = shift;
    my $id    = ident($self);
    my $edges = $edges{$id};
    
    for my $i (@_) {
        my $pos = _find_pos($edges, $i + 1);
        return unless $pos & 1;
    }
    
    return 1;
}

sub contains {
    my $self = shift;
    return $self->contains_all(@_);
}

sub contains_any {
    my $self = shift;
    my $id   = ident($self);
    my $edges = $edges{$id};
    
    for my $i (@_) {
        my $pos = _find_pos($edges, $i + 1);
        return 1 if $pos & 1;
    }
    
    return;
}

sub union {
    my $new = Set::IntSpan::Fast->new();
    $new->merge(@_);
    return $new;
}

sub compliment {
    croak "That's very kind of you - but I expect you meant complement()";
}

sub complement {
    my $self = shift;
    my $new  = $self->copy();
    $new->invert();
    return $new;
}

sub intersection {
    my $new = Set::IntSpan::Fast->new();
    $new->merge(map { $_->complement() } @_);
    $new->invert();
    return $new;
}

sub xor {
    return intersection(union(@_), intersection(@_)->complement());
}

sub diff {
    my $first = shift;
    return intersection($first, union(@_)->complement());
}

sub as_string {
    my $self = shift;
    my $iter = $self->iterate_runs();
    my @runs = ( );
    while (my ($from, $to) = $iter->()) {
        push @runs, $from == $to ? $from : "$from-$to";
    }
    return join(',', @runs);
}

sub as_array {
    my $self = shift;
    my @ar   = ( );
    my $iter = $self->iterate_runs();
    while (my ($from, $to) = $iter->()) {
        push @ar, ( $from .. $to );
    }
    
    return @ar;
}

sub iterate_runs {
    my $self  = shift;
    my $id    = ident($self);

    my $pos   = 0;
    my $edges = $edges{$id};
    
    return sub {
        return if $pos >= scalar(@$edges);
        my @r = ( $edges->[$pos], $edges->[$pos + 1] - 1 );
        $pos += 2;
        return @r;
    };
}

sub cardinality {
    my $self = shift;
    my $card = 0;
    my $iter = $self->iterate_runs();
    while (my ($from, $to) = $iter->()) {
        $card += $to - $from + 1;
    }
    
    return $card;
}

sub subset {
    my $self   = shift;
    my $other  = shift || croak "I need two sets to compare";
    return $self->equals($self->intersection($other));
}

sub superset {
    return subset(reverse(@_));
}

sub equals {
    # Array of array refs
    my @edges = grep { defined($_) }
                map  { $edges{ident($_)} } @_;
    my $medge = scalar(@edges) - 1;
                
    return unless $medge > 0;

    POS: for (my $pos = 0;; $pos++) {
        my $v = $edges[0]->[$pos];
        if (defined($v)) {
            for (@edges[1 .. $medge]) {
                my $vv = $_->[$pos];
                return unless defined($vv) && $vv == $v;
            }
        } else {
            for (@edges[1 .. $medge]) {
                return if defined $_->[$pos];
            }
        }
        
        last POS unless defined($v);
    }

    return 1;
}

1;
__END__

=head1 NAME

Set::IntSpan::Fast - Fast handling of sets containing integer spans.

=head1 VERSION

This document describes Set::IntSpan::Fast version 0.0.2

=head1 SYNOPSIS

    use Set::IntSpan::Fast;
    
    my $set = Set::IntSpan::Fast->new();
    $set->add(1, 3, 5, 7, 9);
    $set->add_range(100, 1_000_000);
    print $set->as_string(), "\n";    # prints 1,3,5,7,9,100-1000000

=head1 DESCRIPTION

The C<Set::IntSpan> module represents sets of integers as a number of
inclusive ranges, for example '1-10,19-23,45-48'. Because many of its
operations involve linear searches of the list of ranges its overall
performance tends to be proportional to the number of distinct ranges.
This is fine for small sets but suffers compared to other possible set
representations (bit vectors, hash keys) when the number of ranges
grows large.

This module also represents sets as ranges of values but stores those
ranges in order and uses a binary search for many internal operations
so that overall performance tends towards O log N where N is the number
of ranges.

The internal representation used by this module is extremely simple: a
set is represented as a list of integers. Integers in even numbered
positions (0, 2, 4 etc) represent the start of a run of numbers while
those in odd numbered positions represent the ends of runs. As an
example the set (1, 3-7, 9, 11, 12) would be represented internally as
(1, 2, 3, 8, 11, 13).

Sets may be infinite - assuming you're prepared to accept that infinity
is actually no more than a fairly large integer. Specifically the
constants C<Set::IntSpan::Fast::NEGATIVE_INFINITY> and
C<Set::IntSpan::Fast::POSITIVE_INFINITY> are defined to be -(2^31-1) and
(2^31-2) respectively. To create an infinite set invert an empty one:

    my $inf = Set::IntSpan::Fast->new()->complement();

Sets need only be bounded in one direction - for example this is the set
of all positive integers (assuming you accept the slightly feeble
definition of infinity we're using):

    my $pos_int = Set::IntSpan::Fast->new();
    $pos_int->add_range(1, $pos_int->POSITIVE_INFINITY);

=head1 INTERFACE

=over

=item C<new()>

Create a new, empty set.

=item C<copy()>

Return an identical copy of the set.

    my $new_set = $set->copy();

=item C<add( $number ... )>

Add the specified integers to the set. Any number of arguments may be
specified in any order. All arguments must be integers between
Set::IntSpan::NEGATIVE_INFINITY and Set::IntSpan::POSITIVE_INFINITY
inclusive.

=item C<remove( $number ... )>

Remove the specified integers from the set. It is not an error to remove
non-members. Any number of arguments may be specified.

=item C<add_range($from, $to)>

Add the inclusive range of integers to the set. Multiple ranges may be
specified:

    $set->add_range(1, 10, 20, 22, 15, 17);

Each pair of arguments constitute a range. The second argument in each
pair must be greater than or equal to the first.

=item C<remove_range($from, $to)>

Remove the inclusive range of integers from the set. Multiple ranges may
be specified:

    $set->remove_range(1, 10, 20, 22, 15, 17);

Each pair of arguments constitute a range. The second argument in each
pair must be greater than or equal to the first.

=item C<invert()>

Complement the set. Because our notion of infinity is actually
disappointingly finite inverting a finite set results in another finite
set. For example inverting the empty set makes it contain all the
integers between NEGATIVE_INFINITY and POSITIVE_INFINITY inclusive.

As noted above NEGATIVE_INFINITY and POSITIVE_INFINITY are actually just
big integers.

=item C<merge( $set ... )>

Merge the members of the supplied sets into this set. Any number of sets
may be supplied as arguments.

=back

=head2 Operators

=over

=item C<complement()>

Returns a new set that is the complement of this set. See the comments
about our definition of infinity above.

=item C<union( $set ... )>

Return a new set that is the union of this set and all of the supplied
sets. May be called either as a method:

    $un = $set->union($other_set);
    
or as a function:

    $un = Set::IntSpan::Fast::union( $set1, $set2, $set3 );

=item C<intersection()>

Return a new set that is the intersection of this set and all the supplied
sets. May be called either as a method:

    $in = $set->intersection($other_set);
    
or as a function:

    $in = Set::IntSpan::Fast::intersection( $set1, $set2, $set3 );

=item C<xor()>

Return a new set that contains all of the members that are in this set
or the supplied set but not both. Can actually handle more than two sets
in which case it returns a set that contains all the members that are in
some of the sets but not all of the sets.

Can be called as a method or a function.

=item C<diff( $set )>

Return a set containing all the elements that are in this set but not the
supplied set.

=back

=head2 Tests

=over

=item C<is_empty()>

Return true if the set is empty.

=item C<contains($number)>

Return true if the specified number is contained in the set.

=item C<contains_any($number, $number, $number ...)>

Return true if the set contains any of the specified numbers.

=item C<contains_all($number, $number, $number ...)>

Return true if the set contains all of the specified numbers.

=item C<cardinality()>

Returns the number of members in the set.

=item C<superset( $set )>

Returns true if this set is a superset of the supplied set. A set is
always a superset of itself, or in other words

    $set->superset($set)
    
returns true.

=item C<subset( $set )>

Returns true if this set is a subset of the supplied set. A set is
always a subset of itself, or in other words

    $set->subset($set)
    
returns true.

=item C<equals( $set )>

Returns true if this set is identical to the supplied set.

=back

=head2 Getting set contents

=over

=item C<as_array()>

Return an array containing all the members of the set in ascending order.

=item C<as_string()>

Return a string representation of the set.

    my $set = Set::IntSpan::Fast->new();
    $set->add(1, 3, 5, 7, 9);
    $set->add_range(100, 1_000_000);
    print $set->as_string(), "\n";    # prints 1,3,5,7,9,100-1000000

=item C<iterate_runs()>

=back

=head2 Constants

The constants NEGATIVE_INFINITY and POSITIVE_INFINITY are exposed. As
noted above these are infinitely smaller than infinity but they're the
best we've got.

=over

=back

=head1 DIAGNOSTICS

=over

=item C<< Range list must have an even number of elements >>

The lists of ranges passed to C<add_range> and C<remove_range> consist
of a number of pairs of integers each of which specify the start and end
of a range.

=item C<< Range limits must be integers >>

You may only add integers to sets.

=item C<< Range limits must be in ascending order >>

When specifying a range in a call to C<add_range> or C<remove_range> the
range bounds must be in ascending order. Multiple ranges don't need to
be in any particular order.

=item C<< Value out of range >>

Sets may only contain values in the range NEGATIVE_INFINITY to
POSITIVE_INFINITY inclusive.

=item C<< That's very kind of you - but I expect you meant complement() >>

The method that complements a set is called C<complement>.

=item C<< I need two sets to compare >>

C<superset> and C<subset> need two sets to compare. The may be called
either as a function:

    $ss = Set::IntSpan::Fast::subset( $s1, $s2 )
    
or as a method:

    $ss = $s1->subset($s2);

=back

=head1 CONFIGURATION AND ENVIRONMENT

=for author to fill in: A full explanation of any configuration
system(s) used by the module, including the names and locations of any
configuration files, and the meaning of any environment variables or
properties that can be set. These descriptions must also include details
of any configuration language used.

Set::IntSpan::Fast requires no configuration files or environment
variables.

=head1 DEPENDENCIES

    Class::Std
    Data::Types
    List::Util

=head1 INCOMPATIBILITIES

Although this module was conceived as a replacement for C<Set::IntSpan>
it isn't a drop-in replacement.

=head1 BUGS AND LIMITATIONS

No bugs have been reported.

Please report any bugs or feature requests to 
C<bug-set-intspan-fast@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.

=head1 AUTHOR

Andy Armstrong C<< <andy@hexten.net> >>

=head1 LICENCE AND COPYRIGHT

Copyright (c) 2006, Andy Armstrong C<< <andy@hexten.net> >>. All
rights reserved.

This module is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>.

=head1 DISCLAIMER OF WARRANTY

BECAUSE THIS SOFTWARE IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY
FOR THE SOFTWARE, TO THE EXTENT PERMITTED BY APPLICABLE LAW. EXCEPT WHEN
OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
PROVIDE THE SOFTWARE "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER
EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE. THE
ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE SOFTWARE IS WITH
YOU. SHOULD THE SOFTWARE PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL
NECESSARY SERVICING, REPAIR, OR CORRECTION.

IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING
WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MAY MODIFY AND/OR
REDISTRIBUTE THE SOFTWARE AS PERMITTED BY THE ABOVE LICENCE, BE
LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL,
INCIDENTAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR
INABILITY TO USE THE SOFTWARE (INCLUDING BUT NOT LIMITED TO LOSS OF
DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR
THIRD PARTIES OR A FAILURE OF THE SOFTWARE TO OPERATE WITH ANY OTHER
SOFTWARE), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE
POSSIBILITY OF SUCH DAMAGES.
