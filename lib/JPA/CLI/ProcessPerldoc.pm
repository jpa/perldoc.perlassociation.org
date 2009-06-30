package JPA::CLI::ProcessPerldoc::Source;
use Moose;

has remote => ( is => 'ro', isa => 'Str', required => 1 );
has name   => ( is => 'ro', isa => 'Str', required => 1 );

package JPA::CLI::ProcessPerldoc;
use Moose;
use MooseX::AttributeHelpers;
use MooseX::Types::Path::Class;
use File::Find::Rule;
use File::Path ();
use File::Temp ();
use Pod::Xhtml;

with 'MooseX::Getopt';
with 'MooseX::SimpleConfig';

has output_dir => (
    is => 'ro',
    isa => 'Path::Class::Dir',
    coerce => 1,
    required => 1
);

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

    my $parser = Pod::Xhtml->new();
    my $cwd = Cwd::cwd();
    my $dir = $self->output_dir;
    # Check out the source code
    foreach my $git_repo ($self->all_sources) {
        chdir $workdir;
        my @cmd;

        $self->execute($self->command('git'), 'clone', $git_repo->remote, $git_repo->name);
        # XXX need to work with the latest version
        chdir $git_repo->name;

        my @modules;
        # Find all pod
        foreach my $file (File::Find::Rule->file->name('*.pod')->in(".")) {
            my $modname = $file;
            $modname =~ s/\//::/g;
            $modname =~ s/\.pod$//;
            my $source = Path::Class::File->new($file);

            $file =~ s/\.pod$/\.html/;
            my $output = $dir->file($git_repo->name, $file);

            if (! -d $output->parent) {
                $output->parent->mkpath;
            }

            $parser->parse_from_file( $source->openr(), $output->openw );

            push @modules, { name => $modname, link => $output->relative( $dir )->relative( $git_repo->name ) };
        }

        my $index = $dir->file($git_repo->name, 'index.html');
        my $fh    = $index->openw;

        print $fh "<html><body><ul>",
            (map { qq|<li><a href="$_->{link}">$_->{name}</a></li>| } @modules),
            "</ul></body></html>"
        ;


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