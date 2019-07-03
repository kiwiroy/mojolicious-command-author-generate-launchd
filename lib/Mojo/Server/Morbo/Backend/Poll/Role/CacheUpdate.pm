package Mojo::Server::Morbo::Backend::Poll::Role::CacheUpdate;

use Mojo::Base qw{-role -signatures};

around modified_files => sub ($orig, $self, @args) {
    return [ @{$self->_cache_updates}, map { [ $_, 'MODIFIED' ] } @{$self->$orig(@args)} ];
};

sub _cache_updates ($self) {
    my $cache = $self->{cache} ||= {};
    my @files;
    for my $file(keys %$cache) {
        push @files, [$file, (-d $file || -l $file) ? 'TYPECHANGED' : 'UNLINKED' ]
            if ! -f $file && delete $cache->{$file};
    }
    return \@files;
}

1;

=encoding utf8

=head1 NAME

Mojo::Server::Morbo::Backend::Poll::Role::CacheUpdate - Poll more than just size / mtime changes

=head1 SYNOPSIS

=head1 DESCRIPTION

A L<Role::Tiny> based role that adds cache updating, and thus file unlink and
type change events to L<Mojo::Server::Morbo::Backend::Poll/"modified_files">.

=head1 METHODS

No new methods are added with this role, but the following are altered in the
composed class.

=head2 modified_files

This method will return an array reference of array references, rather than an
array reference of file paths. The array reference members have a I<file path>
and an I<event type>. The I<event type> can be one of B<MODIFIED>, B<UNLINKED>,
or B<TYPECHANGED>.

=cut
