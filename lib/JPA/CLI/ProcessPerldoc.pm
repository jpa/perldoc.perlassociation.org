package JPA::CLI::ProcessPerldoc::Source;
use Moose;

has remote => ( is => 'ro', isa => 'Str', required => 1 );
has name   => ( is => 'ro', isa => 'Str', required => 1 );

package JPA::CLI::ProcessPerldoc;
use Moose;
use MooseX::AttributeHelpers;
use Path::Class::Dir;
use Path::Class::File;
use File::Find::Rule;
use File::Path ();
use File::Temp ();
use Pod::Xhtml;

with 'MooseX::Getopt';
with 'MooseX::SimpleConfig';

has sources => (
    metaclass => 'Collection::Array',
    is => 'ro',
    isa => 'ArrayRef', #[JPA::CLI::ProcessPerldoc::Source]',
    default => sub { return [] },
    provides => {
        elements => 'all_sources'
    }
);

has workdir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    default => sub {
        my $tempdir = File::Temp::tempdir();
        my $dir = Path::Class::Dir->new( $tempdir );
        $dir->mkpath;
        return $dir;
    }
);

has command_paths => (
    metaclass => 'Collection::Array',
    is => 'ro',
    isa => 'ArrayRef',
    default => sub {
        return [ qw(/opt/local/bin /usr/local/bin /usr/bin /bin /opt/local/sbin /usr/local/sbin /usr/sbin /sbin) ]
    },
    provides => {
        elements => 'all_paths',
    }
);

has commands => (
    metaclass => 'Collection::Hash',
    is => 'ro',
    isa => 'HashRef',
    default => sub { +{} },
    provides => {
        get => 'command_get',
        set => 'command_set',
        exists => 'command_exists',
    }
);

sub command {
    my ($self, $name) = @_;

    if (! $self->command_exists($name)) {
        my $fullpath;
        foreach my $path ($self->all_paths) {
            my $tmp = Path::Class::File->new($path, $name);
            if (-x $tmp) {
                $fullpath = $tmp;
                last;
            }
        }
        if (! $fullpath) {
            confess "$name not found";
        }
        $self->command_set($name, $fullpath);
    }

    return $self->command_get($name);
}

sub execute {
    my ($self, @cmd) = @_;

    if (system(@cmd) != 0) {
        confess "Failed to execute @cmd: $!";
    }
}

sub run {
    my ($self) = @_;
    my $workdir = $self->workdir;

use Data::Dumper;
warn Dumper($self);
    my $parser = Pod::Xhtml->new();
    my $cwd = Cwd::cwd();
    # Check out the source code
    foreach my $git_repo ($self->all_sources) {
        chdir $workdir;
        my @cmd;

        $self->execute($self->command('git'), 'clone', $git_repo->remote, $git_repo->name);
        # XXX need to work with the latest version
        chdir $git_repo->name;

        # Find all pod
        foreach my $file (File::Find::Rule->file->name('*.pod')->in(".")) {
            $file = Path::Class::File->new($file);
            $parser->parse_from_file( $file->openr(), \*STDOUT );
        }

    }
    chdir $cwd;
}

sub DEMOLISH {
    my $self = shift;

    my $workdir = $self->workdir;
    if (-d $workdir) {
        File::Path::remove_tree($workdir);
    }
}

1;