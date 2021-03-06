package App::Ikaros::Builder;
use strict;
use warnings;
use parent qw/Class::Accessor::Fast/;
use Coro;
use Coro::Select;
use Capture::Tiny ':all';
use App::Ikaros::Util qw/run_command_on_remote/;
use App::Ikaros::Installer;
use constant { 
    DEBUG => 0,
    BUILDING => 0,
    BUILD_END => 1,
};

__PACKAGE__->mk_accessors(qw/installer/);

sub new {
    my ($class) = @_;
    return $class->SUPER::new({
        installer => App::Ikaros::Installer->new
    });
}

sub rsync {
    my ($self, $hosts, $rsync_params) = @_;
    return unless $rsync_params;

    my @coros;
    foreach my $host (@$hosts) {
        push @coros, async {
            $self->__rsync($host, $rsync_params);
        };
    }
    $_->join foreach @coros;
}

sub __rsync {
    my ($self, $host, $rsync) = @_;
    my $rsync_cmd = '';
    my $from_dir = $rsync->{from} || '.';
    $rsync_cmd = join ' ', 'rsync', @{$rsync->{opt}}, $from_dir;
    my $dir = $host->workdir . '/' . $rsync->{to};
    run_command_on_remote($host, "mkdir -p $dir");
    my $cmd = sprintf '%s %s@%s:%s', $rsync_cmd, $host->user, $host->hostname, $dir;
    my $status = system $cmd;
    warn "[ERROR] : $cmd. $!" if ($status);
}

sub build {
    my ($self, $hosts) = @_;
    my @coros;
    my %build_status = map { $_->hostname => BUILDING } @$hosts;
    foreach my $host (@$hosts) {
        push @coros, async { 
            $self->__run($host);
            $build_status{$host->hostname} = BUILD_END;
            $self->__display_build_status(\%build_status);
        };
    }
    $_->join foreach @coros;
}

sub __display_build_status {
    my ($self, $build_status) = @_;
    my @building_hosts = grep { $build_status->{$_} == BUILDING } keys(%$build_status);
    print STDERR sprintf "IKAROS:BUILDING_HOSTS %s\n", join(",", @building_hosts);
}

sub __run {
    my ($self, $host) = @_;
    if (DEBUG) {
        my $num = (ref $host->tests eq 'ARRAY') ? scalar @{$host->tests} : 0;
        print $host->hostname . ' : ' . $num, "\n";
    }
    return unless defined $host->tests;

    my $plan = $host->plan;
    my $mkdir = shift @$plan;

    run_command_on_remote($host, $mkdir);
    $self->installer->install_all($host);
    run_command_on_remote($host, $_) foreach (@$plan);

    unlink $host->trigger_filename;
}

1;
