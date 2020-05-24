package App::FirefoxMultiAccountContainersUtils;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Utilities related to Firefox Multi-Account Containers add-on',
    description => <<'_',

About the add-on: <https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/>.

_
};

$SPEC{firefox_mua_sort_containers} = {
    v => 1.1,
    summary => "Sort Firefox Multi-Account Containers add-on's containers",
    description => <<'_',

At the time of this writing, the UI does not provide a way to sort the
containers. Thus this utility.

_
    args => {
        profile => {
            schema => 'firefox::profile_name*',
            req => 1,
            pos => 0,
        },
        #sortsub_routine => {},
        #sortsub_routine_args => {},
    },
};
sub firefox_mua_sort_containers {
    require App::FirefoxUtils;
    require File::Copy;
    require File::Slurper;
    require Firefox::Util::Profile;
    require JSON::MaybeXS;

    my %args = @_;

    my $res;

    $res = App::FirefoxUtils::firefox_is_running();
    return [500, "Can't check if Firefox is running: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;
    return [412, "Please stop Firefox first"] if $res->[2];

    $res = Firefox::Util::Profile::list_firefox_profiles(detail=>1);
    return [500, "Can't list Firefox profiles: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;
    my $path;
    {
        for (@{ $res->[2] }) {
            next unless $_->{name} eq $args{profile};
            $path = $_->{path};
            last;
        }
    }
    return [404, "No such Firefox profile '$args{profile}', ".
                "available profiles include: ".
                join(", ", map {$_->{path}} @{$res->[2]})]
        unless defined $path;

    $path = "$path/containers.json";
    return [412, "Can't find '$path', is this Firefox using Multi-Account Containers?"]
        unless (-f $path);

    log_info "Backing up $path to $path~ ...";
    File::Copy::copy($path, "$path~") or
          return [500, "Can't backup $path to $path~: $!"];

    my $json = JSON::MaybeXS::decode_json(File::Slurper::read_text($path));

    $json->{identities} = [
        sort { $a->{name} cmp $b->{name} } @{ $json->{identities} }
    ];

    log_info "Writing $path ...";
    File::Slurper::write_text($path, JSON::MaybeXS::encode_json($json));
    [200];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

This distribution includes several utilities related to Firefox multi-account
containers addon:

#INSERT_EXECS_LIST


=head1 SEE ALSO

Some other CLI utilities related to Firefox: L<App::FirefoxUtils>,
L<App::DumpFirefoxHistory>.
