=pod

=encoding utf-8

=head1 PURPOSE

Test that Subclass::Of compiles.

Test the exported C<< subclass_of >> function.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.


=cut

use lib "t/lib";
use lib "lib";

use strict;
use warnings;
use Test::More;

BEGIN { use_ok('Subclass::Of') };

my $class = subclass_of(
	"Local::Perl::Class",
	-methods => [
		xyz => sub { 42 },
	],
);

like(
	$class,
	qr{^Local::Perl::Class::},
	'$class seems right',
);

my $object = $class->new;

isa_ok($object, "Local::Perl::Class");
can_ok($object, qw(foo xyz));

is($object->foo, "foo");
is($object->xyz, 42);

done_testing;

