package Subclass::Of;

use 5.008;
use strict;
use warnings;
no strict qw(refs);
no warnings qw(redefine prototype);

BEGIN {
	$Subclass::Of::AUTHORITY = 'cpan:TOBYINK';
	$Subclass::Of::VERSION   = '0.000_04';
}

use B qw(perlstring);
use Carp qw(carp croak);
use Module::Runtime qw(use_package_optimistically module_notional_filename);
use List::MoreUtils qw(all);
use Scalar::Util qw(refaddr);
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

{
	my %i_made_this;
	sub install
	{
		my $me       = shift;
		my $base     = shift or croak "Subclass::Of what?";
		my %opts     = $me->_parse_opts(@_);
		
		my $caller   = $opts{-into}[0];
		my $subclass = $me->_build_subclass($base, \%opts);
		my @aliases  = $opts{-as} ? @{$opts{-as}} : ($base =~ /(\w+)$/);
		
		my $constant = eval sprintf(q/sub () { %s if $] }/, perlstring($subclass));
		$i_made_this{refaddr($constant)} = $subclass;
		
		for my $a (@aliases)
		{
			if (exists &{"$caller\::$a"})
			{
				my $old = $i_made_this{refaddr(\&{"$caller\::$a"})};
				carp(
					$old
						? "Subclass::Of is overwriting alias '$a'; was '$old'; now '$subclass'"
						: "Subclass::Of is overwriting function '$a'",
				);
			}
			*{"$caller\::$a"} = $constant;
		}
		"namespace::clean"->import(-cleanee => $caller, @aliases);
	}
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
		
		push @{$opts{$key}||=[]}, ref eq q(ARRAY) ? @$_ : $_;
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
		
		my $i; $i++ while caller($i) eq __PACKAGE__;
		$INC{module_notional_filename($child)} = (caller($i))[1];
		
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

=for stopwords invocant

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

Create a subclass at runtime, adding roles:

   use Subclass::Of;
   
   my $subclass = subclass_of(
      "My::Class",
      -with => [qw/ My::Role Your::Role His::Role Her::Role /],
   );
   
   my $object = $subclass->new;

=head1 DESCRIPTION

Load a class, creating a subclass of it with additional roles (Moose, Mouse,
Moo and Role::Tiny should all work) and/or additional methods, and providing
a L<lexically-scoped|Sub::Exporter::Lexical> L<alias|aliased> for the
subclass.

=head2 Compile-Time Usage

To create a subclass at compile-time, use the following syntax:

   use SubClass::Of $base_class, %options;

The following options are supported:

=over

=item C<< -methods >>

An arrayref of C<< name => coderef >> pairs of methods that you wish to add
to your subclass.

As you might expect, you can override methods defined in the base class.
However, because of the way C<< $self->SUPER::method() >> is resolved by
Perl, it will not work. Instead a C<< ::SUPER() >> function is provided.
If called with no arguments, then it automatically calls the superclass
method with the same arguments that the subclass was called with; if called
with arguments, then the superclass method gets those arguments exactly.
(If calling it with arguments, remember to include the invocant!)

=item C<< -with >>

The package names of one or more roles (Moose::Role, Role::Tiny, etc) you
wish to apply to your subclass.

=item C<< -package >>

The package name for the subclass. Usually you can ignore this; Subclass::Of
will think one up of its own.

=item C<< -as >>

Subclass::Of will export a lexically scoped alias for the package name. By
lexically scoped I mean:

   {
      use Subclass::Of "LWP::UserAgent", -as => "MyUA";
      # "MyUA" is available here ...
   }
   # ... but not here

By "alias", I mean a constant that returns the subclass' package name as
a string. (See L<aliased>.)

The C<< -as >> option allows you to name this alias. You may request multiple
aliases using an arrayref of strings.

If you don't provide a C<< -as >> option, the last component of the parent
class name (e.g. C<< UserAgent >> for subclasses of L<LWP::UserAgent>)
will be used. If you don't want an alias, try C<< -as => [] >>.

=back

=head2 Run-Time Usage

To create a subclass at compile-time, use the following syntax:

   use Subclass::Of;
   
   my $subclass = subclass_of($base_class, %options);

Note that the C<subclass_of> function is only exported if
C<< use Subclass::Of >> is called with no import list.

The options supported are the same as with compile-time usage, except
C<< -as >> is ignored.

=begin trustme

=item subclass_of

=end trustme

=head2 Wrapping Subclass::Of

If you need to provide a wrapper for Subclass::Of, and thus install scoped
aliases into other packages, use the C<< install >> method:

   require Subclass::Of;
   Subclass::Of->install($base, -into => $target, %options);

=begin trustme

=item install

=end trustme

=head1 DIAGNOSTICS

=over

=item I<< Subclass::Of is overwriting function ... >>

An alias is overwriting an existing sub.

Try setting C<< -as >> to avoid this.

=item I<< Subclass::Of is overwriting alias ... >>

An alias is overwriting an existing sub.

Try setting C<< -as >> to avoid this, or use Subclass::Of in a smaller
lexical scope.

=back

There is no supported method to switch these warnings off. You should
fix the problems they're telling you about.

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

