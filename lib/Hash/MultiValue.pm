package Hash::MultiValue;

use strict;
use 5.008_001;
our $VERSION = '0.02';

use Carp ();
use Scalar::Util qw(refaddr);

my %keys;
my %values;

sub ref { 'HASH' }

sub new {
    my $class = shift;
    my $self = bless { @_ }, $class;

    my $this = refaddr $self;
    my $k = $keys{$this} = [];
    my $v = $values{$this} = [];

    push @{ $_ & 1 ? $v : $k }, $_[$_] for 0 .. $#_;

    $self;
}

sub from_mixed {
    my $class = shift;

    my %hash  = @_ == 1 ? %{$_[0]} : @_;
    my @flat;
    while (my($key, $value) = each %hash) {
        my @v = CORE::ref($value) eq 'ARRAY' ? @$value : ($value);
        push @flat, $key, $_ for @v;
    }

    $class->new(@flat);
}

sub DESTROY {
    my $this = refaddr shift;
    delete $keys{$this};
    delete $values{$this};
}

sub get {
    my($self, $key) = @_;
    $self->{$key};
}

sub get_one {
    my($self, $key) = @_;
    my $this = refaddr $self;
    my $k = $keys{$this};
    my @v = @{$values{$this}}[grep { $key eq $k->[$_] } 0 .. $#$k];

    if (@v == 0) {
        Carp::croak "Key not found: $key";
    } elsif (@v > 1) {
        Carp::croak "Multiple values match: $key";
    } else {
        return $v[0];
    }
}

sub get_all {
    my($self, $key) = @_;
    my $this = refaddr $self;
    my $k = $keys{$this};
    (@{$values{$this}}[grep { $key eq $k->[$_] } 0 .. $#$k]);
}

sub add {
    my $self = shift;
    my $key = shift;
    my $this = refaddr $self;
    $self->{$key} = $_[-1] if @_;
    push @{$keys{$this}}, ($key) x @_;
    push @{$values{$this}}, @_;
}

sub remove {
    my($self, $key) = @_;
    delete $self->{$key};

    my $this = refaddr $self;
    my $k = $keys{$this};
    my $v = $values{$this};
    my @keep = grep { $key ne $k->[$_] } 0 .. $#$k;
    @$k = @$k[@keep];
    @$v = @$v[@keep];
}

sub clear {
    my $self = shift;
    %$self = ();
    my $this = refaddr $self;
    $keys{$this} = [];
    $values{$this} = [];
}

sub clone {
    my $self = shift;
    CORE::ref($self)->new($self->flatten);
}

sub keys {
    my $self = shift;
    my %seen;
    grep { !$seen{$_}++ } @{$keys{refaddr $self}};
}

sub flatten {
    my $self = shift;
    my $this = refaddr $self;
    my $k = $keys{$this};
    my $v = $values{$this};
    map { $k->[$_], $v->[$_] } 0 .. $#$k;
}

sub as_hashref {
    my $self = shift;
    my %hash = %$self;
    \%hash;
}

sub as_hashref_mixed {
    my $self = shift;
    my $this = refaddr $self;
    my $k = $keys{$this};
    my $v = $values{$this};

    my %hash;
    push @{$hash{$k->[$_]}}, $v->[$_] for 0 .. $#$k;
    for (values %hash) {
        $_ = $_->[0] if 1 == @$_;
    }

    \%hash;
}

sub as_hashref_multi {
    my $self = shift;
    my $this = refaddr $self;
    my $k = $keys{$this};
    my $v = $values{$this};

    my %hash;
    push @{$hash{$k->[$_]}}, $v->[$_] for 0 .. $#$k;

    \%hash;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Hash::MultiValue - Store multiple values per key

=head1 SYNOPSIS

  use Hash::MultiValue;

  my $hash = Hash::MultiValue->new(
      foo => 'a',
      foo => 'b',
      bar => 'baz',
  );

  # $hash is an object, but can be used as a hashref and DWIMs!
  my $foo = $hash->{foo};         # 'b' (the last entry)
  my $foo = $hash->get('foo');    # 'b' (always, regardless of context)
  my @foo = $hash->get_all('foo'); # ('a', 'b')

  keys %$hash; # ('foo', 'bar') not guaranteed to be ordered
  $hash->keys; # ('foo', 'bar') guaranteed to be ordered

=head1 DESCRIPTION

Hash::MultiValue is an object (and a plain hash reference) that may
contain multiple values per key, inspired by MultiDict of WebOb.

=head1 WHY THIS MODULE

In a typical web application, the request parameters (a.k.a CGI
parameters) can be single value or multi values. Using CGI.pm style
C<param> is one way to deal with this problem (and it is good, as long
as you're aware of its list context gotcha), but there's another
approach to convert parameters into a hash reference, like Catalyst's
C<< $c->req->parameters >> does, and it B<sucks>.

Why? Because the value could be just a scalar if there is one value
and an array ref if there are multiple, depending on I<user input>
rather than I<how you code it>. So your code should always be like
this to be defensive:

  my $p = $c->req->parameters;
  my @maybe_multi = ref $p->{m} eq 'ARRAY' ? @{$p->{m}} : ($p->{m});
  my $must_single = ref $p->{m} eq 'ARRAY' ? $p->{m}->[0] : $p->{m};

Otherwise you'll get a random runtime exception of I<Can't use string
as an ARRAY ref> or get stringified array I<ARRAY(0xXXXXXXXXX)> as a
string, I<depending on user input> and that is miserable and
insecure.

This module provides a solution to this by making it behave like a
single value hash reference, but also has an API to get multiple
values on demand, explicitly.

=head1 HOW THIS WORKS

The object returned by C<new> is a blessed hash reference that
contains the last entry of the same key if there are multiple values,
but it also keeps the original pair state in the object tracker (a.k.a
inside out objects) and allows you to access the original pairs and
multiple values via the method calls, such as C<get_all> or C<flatten>.

This module does not use C<tie> or L<overload> and is quite fast.

Yes, there is L<Tie::Hash::MultiValue> and this module tries to solve
exactly the same problem, but using a different implementation.

=head1 UPDATING CONTENTS

When you update the content of the hash, B<DO NOT UPDATE> using the
hash reference interface: this won't write through to the tracking
object.

  my $hash = Hash::MultiValue->new(...);

  # WRONG
  $hash->{foo} = 'bar';
  delete $hash->{foo};

  # Correct
  $hash->add(foo => 'bar');
  $hash->remove('foo');

See below for the list of updating methods.

=head1 METHODS

=over 4

=item new

  $hash = Hash::MultiValue->new(@pairs);

Creates a new object that can be treated as a plain hash reference as well.

=item get

  $value = $hash->get($key);
  $value = $hash->{$key};

Returns a single value for the given C<$key>. If there are multiple
values, the last one (not first one) is returned. See below for why.

Note that this B<always> returns the single element as a scalar,
regardless of its context, unlike CGI.pm's C<param> method etc.

=item get_one

  $value = $hash->get_one($key);

Returns a single value for the given C<$key>. This method B<croaks> if
there is no value or multiple values associated with the key, so you
should wrap it with eval or modules like L<Try::Tiny>.

=item get_all

  @values = $hash->get_all($key);

Returns a list of values for the given C<$key>. This method B<always>
returns a list regardless of its context. If there is no value
attached, the result will be an empty list.

=item keys

  @keys = $hash->keys;

Returns a list of keys, in an ordered way.

=item add

  $hash->add($key, $value [, $value ... ]);

Appends a new value to the given C<$key>. This updates the value of
C<< $hash->{$key} >> as well so it always points to the last value.

=item remove

  $hash->remove($key);

Removes a key and associated values for the given C<$key>.

=item clear

  $hash->clear;

Clears the hash to be an empty hash reference.

=item flatten

  @pairs = $hash->flatten;

Gets pairs of keys and values. This should be exactly the same pairs
which are given to C<new> method unless you updated the data.

=item clone

  $new = $hash->clone;

Creates a new Hash::MultiValue object that represents the same data,
but obviously not sharing the reference. It's identical to:

  $new = Hash::MultiValue->new($hash->flatten);

=item as_hashref

  $copy = $hash->as_hashref;

Creates a new plain (unblessed) hash reference where a value is a
single scalar. It's identical to:

  $copy = +{%$hash};

=item as_hashref_mixed

  $mixed = $hash->as_hashref_mixed;

Creates a new plain (unblessed) hash reference where the value is a
single scalar, or an array ref when there are multiple values for a
same key. Handy to create a hash reference that is often used in web
application frameworks request objects such as L<Catalyst>. Ths method
does exactly the opposite of C<from_mixed>.

=item as_hashref_multi

  $multi = $hash->as_hashref_multi

Creates a new plain (unblessed) hash reference where values are all
array references, regardless of there are single or multiple values
for a same key.

=item from_mixed

  $hash = Hash::MultiValue->from_mixed({
      foo => [ 'a', 'b' ],
      bar => 'c',
  });

Creates a new object out of a hash reference where the value is single
or an array ref depending on the number of elements. Handy to convert
from those request objects used in web frameworks such as L<Catalyst>.
This method does exactly the opposite of C<as_hashref_mixed>.

=back

=head1 WHY LAST NOT FIRST?

You might wonder why this module uses the I<last> value of the same
key instead of I<first>. There's no strong reasoning on this decision
since one is as arbitrary as the other, but this is more consistent to
what Perl does:

  sub x {
      return ('a', 'b', 'c');
  }

  my $x = x(); # $x = 'c'

  my %a = ( a => 1 );
  my %b = ( a => 2 );

  my %m = (%a, %b); # $m{a} = 2

When perl gets a list in a scalar context it gets the last entry. Also
if you merge hashes having a same key, the last one wins.

=head1 NOTES ON ref

If you pass this MultiValue hash object to some upstream functions
that you can't control and does things like:

  if (ref $args eq 'HASH') {
      ...
  }

because this is a blessed hash reference it doesn't match and would
fail. To avoid that you should call C<as_hashref> to get a
I<finalized> (= non-blessed) hash reference.

You can also use UNIVERSAL::ref to make it work magically:

  use Hash::MultiValue;

  {
    package Hash::MultiValue; # You need this
    use UNIVERSAL::ref;
  }

and then all C<ref> calls to Hash::MultiValue objects will return I<HASH>.

=head1 AUTHOR

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Aristotle Pagaltzis

Thanks to Michael Peters for the suggestion to use inside-out objects
instead of tie.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=over 4

=item * L<http://pythonpaste.org/webob/#multidict>

=item * L<Tie::Hash::MultiValue>

=back

=cut
