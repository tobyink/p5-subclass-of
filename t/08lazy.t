=pod

=encoding utf-8

=head1 PURPOSE

Test the C<< -lazy >> option.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2017 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

use lib "t/lib";
use lib "lib";

use strict;
use warnings;
use Test::More;

use Subclass::Of "Local::Perl::Class" => (
	-lazy,
	-package => 'Example::Subclass::Blah',
	-methods => [
		xyz => sub { 42 },
	],
);

ok not 'Example::Subclass::Blah'->can('foo');
ok not 'Example::Subclass::Blah'->can('xyz');

# generates the class
is(Class, 'Example::Subclass::Blah');

ok 'Example::Subclass::Blah'->can('foo');
ok 'Example::Subclass::Blah'->can('xyz');

# memoized
is(Class, 'Example::Subclass::Blah');

done_testing;

