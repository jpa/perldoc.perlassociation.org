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
use Template;
use YAML::XS qw(LoadFile);

with 'MooseX::Getopt';
with 'MooseX::SimpleConfig';

has template => (
    is => 'ro',
    isa => 'Template',
    lazy => 1,
    default => sub {
        my $self = shift;
        return Template->new( $self->template_args );
    }
);

has template_args => (
    is => 'ro',
    isa => 'HashRef',
    required => 1,
);
    
has pod_parser => (
    is => 'ro',
    isa => 'Pod::Xhtml',
    default => sub {
        return Pod::Xhtml->new(
            StringMode => 1,
	    FragmentOnly=>1,
	    TopHeading => 2,
            TopLinks   => 0        )
    },
);

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

sub create_index {
	my ($self) = @_;

    my $template = $self->template;
    $template->process( 
        "index.tt",
        {
            modules => [ $self->all_sources ],
        },
        $self->output_dir()->file('index.html')->stringify,
    ) || confess $template->error;
}

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
    # Check out the source code
    $self->create_index();
    foreach my $git_repo ($self->all_sources) {
        $self->process_repo( $git_repo );
    }
}

sub process_repo {
    my ($self, $git_repo) = @_;

    my $workdir = $self->workdir;
    my $cwd = Cwd::cwd();
    eval {
        chdir $workdir;
        $self->execute($self->command('git'), 'clone', $git_repo->remote, $git_repo->name);

        chdir $git_repo->name;
        $self->process_pod($git_repo);
    };
    my $e = $@;

    chdir $cwd;

    if ($e) {
        confess $e;
    }
}

sub process_pod {
    my ($self, $git_repo) = @_;

    # find out version
    my $meta = LoadFile( 'META.yml' );
    my $version = $meta->{version};
    my $dist    = $meta->{distribution};

    my @cmd;
    my $parser = $self->pod_parser();
    my $dir = $self->output_dir->subdir('pod');
    my $template = $self->template;

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

        $parser->parse_from_file( $source->openr() );

        my $xhtml = '[% WRAPPER wrapper.tt, page.title => module _ " " _ dist _ "(" _ version _ ")" %]<h1>[% module | html %]</h1>'."\n";

        $xhtml .= $parser->asString();
	$xhtml .= '[% END %]';

        $template->process( \$xhtml, { version => $version, module => $modname, dist => $dist }, $output->stringify ) ||
            confess $template->error;

            push @modules, { version => $version, name => $modname, link => $output->relative( $dir )->relative( $git_repo->name ) };
    }

    $template->process(
        'pod/index.tt',
        { dist => $dist, modules => \@modules, version => $version }, 
        $dir->file($git_repo->name, 'index.html')->stringify,
    ) || confess $template->error;
}

sub DEMOLISH {
    my $self = shift;

    my $workdir = $self->workdir;
    if (-d $workdir) {
        File::Path::remove_tree($workdir);
    }
}

1;
