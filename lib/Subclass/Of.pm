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

my $_v;
sub import
{
	my $caller   = caller;
	my $me       = shift;
	my $base     = shift or return;
	my ($opts)   = +{ $me->_parse_opts(@_) };
	
	my $subclass = $me->_build_subclass($base, $opts);
	my ($as)     = ($base =~ /(\w+)$/);
	
	*{"$caller\::$_"} = eval sprintf(q{sub(){%s}}, perlstring($subclass))
		for ($opts->{-as} ? @{$opts->{-as}} : $as);
}

sub _parse_opts
{
	shift;
	
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

sub _detect_oo
{
	my $package = $_[0];
	return "" unless $package->can("meta");
	return "Moo"   if ref($package->meta) eq "Moo::HandleMoose::FakeMetaClass";
	return "Mouse" if $package->meta->isa("Mouse::Meta::Module");
	return "Moose" if $package->meta->isa("Moose::Meta::Class");
	return "Moose" if $package->meta->isa("Moose::Meta::Role");
	return "";
}

my %count;
sub _build_subclass
{
	my $me = shift;
	my ($parent, $opts) = @_;
	
	my $child = (
		$opts->{-package} ||= [ sprintf('%s::__SUBCLASS__::%04d', $parent, ++$count{$parent}) ]
	)->[0];
	
	my $oo = _detect_oo(use_package_optimistically($parent));
	
	$me->_build_subclass_moose($parent, $child, $opts) if $oo eq "Moose";
	$me->_build_subclass_mouse($parent, $child, $opts) if $oo eq "Moose";
	$me->_build_subclass_moo($parent, $child, $opts)   if $oo eq "Moo";
	$me->_build_subclass_raw($parent, $child, $opts)   if $oo eq "";
	
	return $child;
}

sub _build_subclass_moose
{
	my $me = shift;
	my ($parent, $child, $opts) = @_;
	
	my $meta = "Moose::Meta::Class"->new(
		$opts->{-package}[0],
		superclasses => [$parent],
		methods      => $me->_make_method_hash($child, $opts),
	);
	
	$me->_apply_roles($meta->name, $opts);
	
	return $meta->name;
}

sub _build_subclass_mouse
{
	croak "$_[0] is a Mouse class; not currently supported";
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
	
	my $methods = $me->_make_method_hash($child, $opts);
	for my $name (sort keys %$methods)
	{
		*{"$child\::$name"} = $methods->{$name};
	}
}

sub _build_subclass_raw
{
	my $me = shift;
	my ($parent, $child, $opts) = @_;
	
	@{"$child\::ISA"} = $parent;
	
	my $methods = $me->_make_method_hash($child, $opts);
	for my $name (sort keys %$methods)
	{
		*{"$child\::$name"} = $methods->{$name};
	}
	
	$me->_apply_roles($child, $opts);
}

sub _apply_roles
{
	my $me = shift;
	my ($pkg, $opts) = @_;
	my @roles = map use_package_optimistically($_), @{ $opts->{-with} || [] };
	
	return unless @roles;
	my $oo = _detect_oo($pkg);
	
	if ($oo eq "Moo")
	{
		return "Moo::Role"->apply_roles_to_package($pkg, @roles);
	}
	elsif ($oo eq "Moose")
	{
		return Moose::Util::apply_all_roles($pkg, @roles);
	}
	elsif ($oo eq "Mouse")
	{
		return Mouse::Util::apply_all_roles($pkg, @roles);
	}
	
	if (all { _detect_oo($_) eq "" } @roles)
	{
		require Role::Tiny;
		"Role::Tiny"->apply_roles_to_package($pkg, @roles);
	}
	else
	{
		require Moo::Role;
		"Moo::Role"->apply_roles_to_package($pkg, @roles);
	}
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

