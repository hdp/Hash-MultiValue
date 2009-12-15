use strict;
use Test::More;
use Hash::MultiValue;

my $hash = Hash::MultiValue->new(
    foo => 'a',
    foo => 'b',
    bar => 'baz',
);

$hash->{baz} = 33;
is $hash->{baz}, 33;

my $new_hash = Hash::MultiValue->new($hash->flatten);
is_deeply $hash, $new_hash;

delete $hash->{foo};

is_deeply [ sort keys %$hash ], [ qw(bar baz) ];

done_testing;
