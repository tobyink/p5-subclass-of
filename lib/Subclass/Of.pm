package Subclass::Of;

use strict;
use warnings;
no strict qw(refs);
no warnings qw(redefine prototype);

BEGIN {
	$Subclass::Of::AUTHORITY = 'cpan:TOBYINK';
	$Subclass::Of::VERSION   = '0.000_01';
}

use B qw(perlstring);
use Carp qw(croak);
use Module::Runtime qw(use_package_optimistically);
use List::MoreUtils qw(all);
use Sub::Name qw(subname);
use namespace::clean;

our ($SUPER_PKG, $SUPER_SUB, $SUPER_ARG);
our @EXPORT = qw(subclass_of);

my $_v;
sub import
{
	my $me = shift;
	
	return $me->install(@_, -into => scalar caller) if @_;
	
	require Exporter::TypeTiny;
	our @ISA = "Exporter::TypeTiny";
	@_ = $me;
	goto \&Exporter::TypeTiny::import;
}

sub install
{
	my $me       = shift;
	my $base     = shift or croak "Subclass::Of what?";
	my %opts     = $me->_parse_opts(@_);
	
	my $caller   = $opts{-into}[0];
	my $subclass = $me->_build_subclass($base, \%opts);
	my @aliases  = $opts{-as} ? @{$opts{-as}} : ($base =~ /(\w+)$/);
	
	*{"$caller\::$_"} = eval sprintf(q{sub(){%s}}, perlstring($subclass)) for @aliases;
	"namespace::clean"->import(-cleanee => $caller, @aliases);
}

sub subclass_of
{
	my $base     = shift or croak "Subclass::Of what?";
	my %opts     = __PACKAGE__->_parse_opts(@_);
	
	return __PACKAGE__->_build_subclass($base, \%opts);
}

sub _parse_opts
{
	shift;
	
	if (@_==1 and ref($_[0]) eq q(HASH))
	{
		return %{$_[0]};
	}
	
	my %opts;
	my $key = undef;
	while (@_)
	{
		$_ = shift;
		
		if (defined and !ref and /^-/) {
			$key = $_;
			next;
		}
		
		push @{$opts{$key}}, ref eq q(ARRAY) ? @$_ : $_;
	}
	
	return %opts;
}

{
	my %_detect_oo; # memoize
	sub _detect_oo
	{
		my $pkg = $_[0];
		
		return $_detect_oo{$pkg} if exists $_detect_oo{$pkg};
		
		# Use metaclass to determine the OO framework in use.
		# 
		return $_detect_oo{$pkg} = ""
			unless $pkg->can("meta");
		return $_detect_oo{$pkg} = "Moo"
			if ref($pkg->meta) eq "Moo::HandleMoose::FakeMetaClass";
		return $_detect_oo{$pkg} = "Mouse"
			if $pkg->meta->isa("Mouse::Meta::Module");
		return $_detect_oo{$pkg} = "Moose"
			if $pkg->meta->isa("Moose::Meta::Class");
		return $_detect_oo{$pkg} = "Moose"
			if $pkg->meta->isa("Moose::Meta::Role");
		return $_detect_oo{$pkg} = "";
	}
}

{
	my %count;
	sub _build_subclass
	{
		my $me = shift;
		my ($parent, $opts) = @_;
		
		my $child = (
			$opts->{-package} ||= [ sprintf('%s::__SUBCLASS__::%04d', $parent, ++$count{$parent}) ]
		)->[0];
		
		my $oo     = _detect_oo(use_package_optimistically($parent));	
		my $method = $oo ? lc "_build_subclass_$oo" : "_build_subclass_raw";
		
		$me->$method($parent, $child, $opts);
		$me->_apply_methods($child, $opts);	
		$me->_apply_roles($child, $opts);

		return $child;
	}
}

sub _build_subclass_moose
{
	my $me = shift;
	my ($parent, $child, $opts) = @_;
	
#	"Moose::Meta::Class"->initialize($child, superclasses => [$parent]);

	eval sprintf(q{
		package %s;
		use Moose;
		extends %s;
		use namespace::clean;
	}, $child, perlstring($parent));	
}

sub _build_subclass_mouse
{
	my $me = shift;
	my ($parent, $child, $opts) = @_;
	
	eval sprintf(q{
		package %s;
		use Mouse;
		extends %s;
		use namespace::clean;
	}, $child, perlstring($parent));	
}

sub _build_subclass_moo
{
	my $me = shift;
	my ($parent, $child, $opts) = @_;
	
	eval sprintf(q{
		package %s;
		use Moo;
		extends %s;
		use namespace::clean;
	}, $child, perlstring($parent));
}

sub _build_subclass_raw
{
	my $me = shift;
	my ($parent, $child, $opts) = @_;
	
	@{"$child\::ISA"} = $parent;
}

sub _apply_methods
{
	my $me = shift;
	my ($pkg, $opts) = @_;
	
	my $methods = $me->_make_method_hash($pkg, $opts);
	for my $name (sort keys %$methods)
	{
		*{"$pkg\::$name"} = $methods->{$name};
	}
}

sub _apply_roles
{
	my $me = shift;
	my ($pkg, $opts) = @_;
	my @roles = map use_package_optimistically($_), @{ $opts->{-with} || [] };
	
	return unless @roles;
	
	# All roles appear to be Role::Tiny; use Role::Tiny to
	# handle composition.
	# 
	if (all { _detect_oo($_) eq "" } @roles)
	{
		require Role::Tiny;
		return "Role::Tiny"->apply_roles_to_package($pkg, @roles);
	}
	
	# Otherwise, role composition is determined by the OO framework
	# of the base class.
	# 
	my $oo = _detect_oo($pkg);
	
	if ($oo eq "Moo")
	{
		return "Moo::Role"->apply_roles_to_package($pkg, @roles);
	}
	
	if ($oo eq "Moose")
	{
		return Moose::Util::apply_all_roles($pkg, @roles);
	}
	
	if ($oo eq "Mouse")
	{
		return Mouse::Util::apply_all_roles($pkg, @roles);
	}
	
	# If all else fails, try using Moo because it understands quite
	# a lot about Moose and Mouse.
	# 
	require Moo::Role;
	"Moo::Role"->apply_roles_to_package($pkg, @roles);
}

sub _make_method_hash
{
	shift;
	
	my $pkg     = $_[0];
	my $r       = {};
	my @methods = @{ $_[1]{-methods} || [] };
	
	while (@methods)
	{
		my ($name, $code) = splice(@methods, 0, 2);
		
		$name =~ /^\w+/ or croak("Not a valid method name: $name");
		ref($code) eq q(CODE) or croak("Not a code reference: $code");
		
		$r->{$name} = subname "$pkg\::$name", sub {
			local $SUPER_PKG = $pkg;
			local $SUPER_SUB = $name;
			local $SUPER_ARG = \@_;
			$code->(@_);
		};
	}
	
	return $r;
}

sub ::SUPER
{
	eval { require mro } or do { require MRO::Compat };
	
	my ($super) =
		map   { \&{ "$_\::$SUPER_SUB" } }
		grep  { exists &{"$_\::$SUPER_SUB"} }
		grep  { $_ ne $SUPER_PKG }
		@{ mro::get_linear_isa($SUPER_PKG) };
	
	croak qq[Can't locate object method "$SUPER_SUB" via package "$SUPER_PKG"]
		unless $super;
	
	@_ = @$SUPER_ARG unless @_;
	goto $super;
}

1;

__END__

=pod

=encoding utf-8

=head1 NAME

Subclass::Of - import a magic subclass

=head1 SYNOPSIS

Create a subclass overriding a method:

	use Subclass::Of "LWP::UserAgent",
		-as      => "ImpatientUA",
		-methods => [
			sub new {
				my $self = ::SUPER();
				$self->timeout(15);
				$self->max_redirect(3);
				return $self;
			}
		];
	
	my $ua = ImpatientUA->new;

Create a subclass, adding roles:

	use Subclass::Of "Some::Class",
		-with => [qw/ My::Role Your::Role Another::Role /];
	
	my $thing = Class->new;

=head1 DESCRIPTION

Load a class, creating a subclass of it with additional roles (Moose, Mouse,
Moo and Role::Tiny should all work) and/or additional methods.

=head1 CAVEATS

Certain class builders don't play nice with certain role builders.
Moose classes should be able to consume a mixture of Moose and Moo roles.
Moo classes should be able to consume a mixture of Moose, Moo, Mouse and Role::Tiny roles.
Mouse classes should be able to consume Mouse roles.
Any class should be able to consume Role::Tiny roles, provided you don't try to mix in other roles at the same time.
(For example, a Mouse class can consume a Role::Tiny role, but it can't consume a Role::Tiny role and a Mouse role simultaneously.)

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Subclass-Of>.

=head1 SEE ALSO

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

