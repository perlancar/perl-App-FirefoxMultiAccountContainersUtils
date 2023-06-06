package App::FirefoxMultiAccountContainersUtils;

use 5.010001;
use strict 'subs', 'vars';
use warnings;
use Log::ger;

use Sort::Sub ();

# AUTHORITY
# DATE
# DIST
# VERSION

$Sort::Sub::argsopt_sortsub{sort_sub}{cmdline_aliases} = {S=>{}};
$Sort::Sub::argsopt_sortsub{sort_args}{cmdline_aliases} = {A=>{}};

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Utilities related to Firefox Multi-Account Containers add-on',
    description => <<'_',

About the add-on: <https://addons.mozilla.org/en-US/firefox/addon/multi-account-containers/>.

_
};

our %argspec0_profile = (
    profile => {
        # XXX not observed yet by pericmd-lite when setting default value for
        # args, only 'default' clause is checked. so we currently still set
        # default value manually in _get_containers_json
        schema => 'firefox::local_profile_name::default_first*',
        pos => 0,
    },
);

our %argspecopt_profile = (
    profile => {
        # XXX not observed yet by pericmd-lite when setting default value for
        # args, only 'default' clause is checked. so we currently still set
        # default value manually in _get_containers_json
        schema => 'firefox::local_profile_name::default_first*',
    },
);

sub _get_containers_json {
    require App::FirefoxUtils;
    require File::Copy;
    require File::Slurper;
    require Firefox::Util::Profile;
    require JSON::MaybeXS;

    my ($args, $do_backup) = @_;

    my $res;

    if ($do_backup) {
        $res = App::FirefoxUtils::firefox_is_running();
        return [500, "Can't check if Firefox is running: $res->[0] - $res->[1]"]
            unless $res->[0] == 200;
        if ($args->{-dry_run}) {
            log_info "[DRY-RUN] Note that Firefox is still running, ".
                "you should stop Firefox first when actually modifying containers";
        } else {
            return [412, "Please stop Firefox first"] if $res->[2];
        }
    }

    $res = Firefox::Util::Profile::list_firefox_profiles(detail=>1);
    return [500, "Can't list Firefox profiles: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;

    # set default value of args, this will eventually be removed if pericmd has
    # observed x.perl.default_value_rules
    #use DDC; print "D1:"; dd $args;
    $args->{profile} //= $res->[2][0]{name};
    #use DDC; print "D2:"; dd $args;

    my $path;
    {
        for (@{ $res->[2] }) {
            next unless $_->{name} eq $args->{profile};
            $path = $_->{path};
            last;
        }
    }
    return [404, "No such Firefox profile '$args->{profile}', ".
                "available profiles include: ".
                join(", ", map {$_->{name}} @{$res->[2]})]
        unless defined $path;

    $path = "$path/containers.json";
    return [412, "Can't find '$path', is this Firefox using Multi-Account Containers?"]
        unless (-f $path);

    unless ($args->{-dry_run} || !$do_backup) {
        log_info "Backing up $path to $path~ ...";
        File::Copy::copy($path, "$path~") or
              return [500, "Can't backup $path to $path~: $!"];
    }

    my $json = JSON::MaybeXS::decode_json(File::Slurper::read_text($path));

    [200, "OK", {path=>$path, content=>$json}];
}

sub _complete_container {
    require Firefox::Util::Profile;

    my %args = @_;

    # XXX if firefox profile is already specified, only list containers for that
    # profile.
    my $res = Firefox::Util::Profile::list_firefox_profiles();
    $res->[0] == 200 or return {message => "Can't list Firefox profiles: $res->[0] - $res->[1]"};

    my %containers;
    for my $profile (@{ $res->[2] }) {
        my $cres = firefox_mua_list_containers(profile => $profile);
        $cres->[0] == 200 or next;
        for (@{ $cres->[2] }) {
            next unless $_->{public};
            next unless $_->{name};
            $containers{ $_->{name} }++;
        }
    }
    Complete::Util::complete_hash_key(
        word => $args{word},
        hash => \%containers,
    );
}

$SPEC{firefox_mua_list_containers} = {
    v => 1.1,
    summary => "List Firefox Multi-Account Containers add-on's containers",
    args => {
        %argspec0_profile,
    },
};
sub firefox_mua_list_containers {
    my %args = @_;

    my $res;
    $res = _get_containers_json(\%args, 0);
    return $res unless $res->[0] == 200;
    my $json = $res->[2]{content};

    # convert boolean object to 1/0 for display
    for (@{ $json->{identities} }) { $_->{public} = $_->{public} ? 1:0 }
    return [200, "OK", $json->{identities}];
}

$SPEC{firefox_mua_modify_containers} = {
    v => 1.1,
    summary => "Modify (and delete) Firefox Multi-Account Containers add-on's containers with Perl code",
    description => <<'_',

This utility lets you modify the identity records in `containers.json` file
using Perl code. The Perl code is called for every container (record). It is
given the record hash in `$_` and is supposed to modify and return the modified
the record. It can also choose to return false to instruct deleting the record.

_
    args => {
        %argspec0_profile,
        code => {
            schema => ['any*', of=>['code*', 'str*']],
            req => 1,
            pos => 1,
        },
    },
    features => {
        dry_run => 1,
    },
    examples => [
        {
            summary => 'Delete all containers matching some conditions (remove -n to actually delete it)',
            argv => ['myprofile', 'return 0 if $_->{icon} eq "cart" || $_->{name} =~ /temp/i; $_'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Delete all containers (remove -n to actually delete it)',
            argv => ['myprofile', '0'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Change all icons to "dollar" and all colors to "red"',
            argv => ['myprofile', '$_->{icon} = "dollar"; $_->{color} = "red"; $_'],
            test => 0,
            'x.doc.show_result' => 0,
        },
    ],
};
sub firefox_mua_modify_containers {
    require File::Slurper;

    my %args = @_;

    my $code = $args{code};
    unless (ref $code eq 'CODE') {
        $code = "no strict; no warnings; package main; sub { $code }";
        $code = eval $code; ## no critic: BuiltinFunctions::ProhibitStringyEval
        return [400, "Cannot compile string code: $@"] if $@;
    }

    my $res;
    $res = _get_containers_json(\%args, 'backup');
    return $res unless $res->[0] == 200;

    my $path = $res->[2]{path};
    my $json = $res->[2]{content};
    my $new_identities = [];
    for my $identity (@{ $json->{identities} }) {
        local $_ = $identity;
        my $code_res = $code->($identity);
        if (!$code_res) {
            next;
        } elsif (ref $code_res ne 'HASH') {
            log_fatal "Code does not return a hashref: %s", $code_res;
            die;
        } else {
            push @$new_identities, $code_res;
        }
    }
    $json->{identities} = $new_identities;

    if ($args{-dry_run}) {
        # convert boolean object to 1/0 for display
        for (@{ $json->{identities} }) { $_->{public} = $_->{public} ? 1:0 }

        return [200, "OK (dry-run)", $json->{identities}];
    }

    log_info "Writing $path ...";
    File::Slurper::write_text($path, JSON::MaybeXS::encode_json($json));
    [200];
}

$SPEC{firefox_mua_add_container} = {
    v => 1.1,
    summary => "Add a new Firefox Multi-Account container",
    description => <<'_',

This utility will copy the last container record, change the name to the one you
specify, and add it to the list of containers. You can also set some other
attributes.

_
    args => {
        %argspec0_profile,
        name => {
            summary => 'Name for the new container',
            schema => ['str*', min_len=>1],
            pos => 1,
        },
        color => {
            schema => ['str*', match=>qr/\A\w+\z/], # XXX currently not validated for valid values
        },
        icon => {
            schema => ['str*', match=>qr/\A\w+\z/], # XXX currently not validated for valid values
        },
    },
    features => {
        dry_run => 1,
    },
};
sub firefox_mua_add_container {
    require App::FirefoxUtils;
    require File::Copy;
    require File::Slurper;
    require Firefox::Util::Profile;
    require JSON::MaybeXS;

    my %args = @_;
    defined(my $name = $args{name}) or return [400, "Please specify name for new container"];

    my $res;
    $res = _get_containers_json(\%args, 'backup');
    return $res unless $res->[0] == 200;

    my $path = $res->[2]{path};
    my $json = $res->[2]{content};

    # we currently need one existing identity
    @{ $json->{identities} } or return [412, "I need at least one existing identity"];
    my $new_identity = { %{$json->{identities}[-1]} };
    $new_identity->{name} = $name;

    # check that name does not already exist
    for my $identity (@{ $json->{identities} }) {
        return [409, "Identity with name '$name' already exists"] if $identity->{name} eq $name;
    }

    # set other attributes
    if (defined $args{icon}) {
        $new_identity->{icon} = $args{icon};
    }
    if (defined $args{color}) {
        $new_identity->{color} = $args{color};
    }

    # set user context id to the greatest
    {
        my $max_context_id = 0;
        for my $identity (@{ $json->{identities} }) {
            $max_context_id = $identity->{userContextId}
                if $max_context_id < $identity->{userContextId}
                && $identity->{userContextId} < 4294967295;
        }
        $new_identity->{userContextId} = $max_context_id;
    }

    # add the new container
    push @{ $json->{identities} }, $new_identity;

    if ($args{-dry_run}) {
        # convert boolean object to 1/0 for display
        for (@{ $json->{identities} }) { $_->{public} = $_->{public} ? 1:0 }

        return [200, "OK (dry-run)", $json->{identities}[-1]];
    }

    log_info "Writing $path ...";
    File::Slurper::write_text($path, JSON::MaybeXS::encode_json($json));
    [200];
}

$SPEC{firefox_mua_sort_containers} = {
    v => 1.1,
    summary => "Sort Firefox Multi-Account Containers add-on's containers",
    description => <<'_',

This utility was written when the Firefox Multi-Account Containers add-on does
not provide a way to reorder the containers. Now it does; you can click Manage
Containers then use the hamburger button to drag the containers up and down to
reorder.

However, this utility is still useful particularly when you have lots of
containers and want to sort it in some way. This utility provides a flexible
sorting mechanism via using <pm:Sort:Sub> modules. For example:

    % firefox-mua-sort-containers MYPROFILE
    % firefox-mua-sort-containers MYPROFILE -S by_example -A example=foo,bar,baz,qux

will first sort your containers asciibetically, then put specific containers
that you use often (`foo`, `bar`, `baz`, `qux`) at the top.

_
    args => {
        %argspec0_profile,
        %Sort::Sub::argsopt_sortsub,
    },
    features => {
        dry_run => 1,
    },
};
sub firefox_mua_sort_containers {
    require App::FirefoxUtils;
    require File::Copy;
    require File::Slurper;
    require Firefox::Util::Profile;
    require JSON::MaybeXS;

    my %args = @_;

    my $sort_sub  = $args{sort_sub}  // 'asciibetically';
    my $sort_args = $args{sort_args} // [];
    my $cmp = Sort::Sub::get_sorter($sort_sub, { map { split /=/, $_, 2 } @$sort_args });

    my $res;
    $res = _get_containers_json(\%args, 'backup');
    return $res unless $res->[0] == 200;

    my $path = $res->[2]{path};
    my $json = $res->[2]{content};
    $json->{identities} = [
        sort {
            my $a_name = defined$a->{name} ? $a->{name} : do { my $name = lc $a->{l10nID}; $name =~ s/^usercontext//; $name =~ s/\.label$//; $name };
            my $b_name = defined$b->{name} ? $b->{name} : do { my $name = lc $b->{l10nID}; $name =~ s/^usercontext//; $name =~ s/\.label$//; $name };
            $sort_sub eq 'by_perl_code' ? $cmp->($a, $b) : $cmp->($a_name, $b_name)
        }  @{ $json->{identities} }
    ];

    if ($args{-dry_run}) {
        # convert boolean object to 1/0 for display
        for (@{ $json->{identities} }) { $_->{public} = $_->{public} ? 1:0 }

        return [200, "OK (dry-run)", $json->{identities}];
    }

    log_info "Writing $path ...";
    File::Slurper::write_text($path, JSON::MaybeXS::encode_json($json));
    [200];
}

$SPEC{firefox_mua_dump_identities_json} = {
    v => 1.1,
    summary => "Dump the content of identities.json",
    description => <<'_',

_
    args => {
        %argspec0_profile,
    },
};
sub firefox_mua_dump_identities_json {
    require App::FirefoxUtils;
    require Firefox::Util::Profile;
    require JSON::MaybeXS;

    my %args = @_;

    my $res;
    $res = _get_containers_json(\%args);
    return $res unless $res->[0] == 200;

    my $path = $res->[2]{path};
    my $json = $res->[2]{content};

    [200, "OK", $json];
}

$SPEC{open_firefox_container} = {
    v => 1.1,
    summary => "CLI to open URL in a new Firefox tab, in a specific multi-account container",
    description => <<'_',

This utility opens a new firefox tab in a specific multi-account container. This
requires the Firefox Multi-Account Containers add-on, as well as another add-on
called "Open external links in a container",
<https://addons.mozilla.org/en-US/firefox/addon/open-url-in-container/>.

The way it works, because add-ons currently do not have hooks to the CLI, is via
a custom protocol handler. For example, if you want to open
<http://www.example.com/> in a container called `mycontainer`, you ask Firefox
to open this URL:

    ext+container:name=mycontainer&url=http://www.example.com/

Ref: <https://github.com/mozilla/multi-account-containers/issues/365>

_
    args => {
        %argspecopt_profile,
        container => {
            schema => 'str*',
            completion => \&_complete_container,
            req => 1,
            pos => 0,
        },
        urls => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'url',
            schema => ['array*', of=>'str*'],
            pos => 1,
            slurpy => 1,
        },
        extra_firefox_options_before => {
            summary => 'Additional options (arguments) to put before the URLs',
            schema => ['array*', of=>'str*'],
            cmdline_aliases => {'b'=>{}},
        },
        extra_firefox_options_after => {
            summary => 'Additional options (arguments) to put after the URLs',
            schema => ['array*', of=>'str*'],
            cmdline_aliases => {'a'=>{}},
        },
    },
    features => {
    },
    examples => [
        {
            summary => 'Open two URLs in a container called "mycontainer"',
            argv => [qw|mycontainer www.example.com www.example.com/url2|],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'If URL is not specified, will open a blank tab',
            argv => [qw|mycontainer|],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Open URL in a new tab in a new window',
            argv => [qw|mycontainer www.example.com -b --new-window|],
            test => 0,
            'x.doc.show_result' => 0,
            description => <<'_',

This command passes the `--new-window` option to `firefox`.

_
        },
    ],
    links => [
        {url=>'prog:open-browser'},
    ],
};
sub open_firefox_container {
    require URI::Escape;

    my %args = @_;
    my $container = $args{container};

    my @urls;
    for my $url0 (@{ $args{urls} || ["about:blank"] }) {
        my $url = "ext+container:";
        $url .= "name=" . URI::Escape::uri_escape($container);
        $url .= "&url=" . URI::Escape::uri_escape($url0);
        push @urls, $url;
    }

    my @cmd = (
        "firefox",
        @{$args{extra_firefox_options_before} // []},
        @urls,
        @{$args{extra_firefox_options_after} // []},
    );
    log_trace "Executing %s ...", \@cmd;
    exec @cmd;
    #[200]; # won't be reached
}

1;
# ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

This distribution includes several utilities related to Firefox multi-account
containers addon:

#INSERT_EXECS_LIST


=head1 SEE ALSO

"Open external links in a container" add-on,
L<https://addons.mozilla.org/en-US/firefox/addon/open-url-in-container/> (repo
at L<https://github.com/honsiorovskyi/open-url-in-container/>). The add-on also
comes with a bash launcher script:
L<https://github.com/honsiorovskyi/open-url-in-container/blob/master/bin/launcher.sh>.
This C<firefox-container> Perl script is a slightly enhanced version of that
launcher script.

Some other CLI utilities related to Firefox: L<App::FirefoxUtils>,
L<App::DumpFirefoxHistory>.
