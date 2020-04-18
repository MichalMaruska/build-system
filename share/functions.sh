#! /usr/bin/zsh

# Common functions for the scripts
info()
{
    cecho yellow $1 >&2
}

check_getopt()
{
    if getopt -T; then # should test (( $? = -4 ))
        echo "incompatible  getopt(1) installed. Abort"
        exit -1
    fi
}

# the hook betwen git-checkout & build.
prepare_hook_name()
{
    # Support for 2 different versions of gbp:
    local gbp_version=$(gbp buildpackage --version|cut --delimiter=' ' --fields=2)

    if dpkg --compare-versions $gbp_version 'gt' 0.6; then
        PREVERSION_HOOK_NAME=--git-postexport
    else
        PREVERSION_HOOK_NAME=--git-prebuild
    fi
}

# set -x set inside a function does not work globally?
possibly_trace()
{
    if [ -n "${DEBUG-}" ]; then
        # cecho blue setting DEBUGGING on >&2
        # setopt XTRACE
        # unsetopt LOCAL_OPTIONS
        echo "set -x"
    fi
}


# Keep only the 2-numbers NNN.MMMwhatever
drop_verbal_suffix()
{
    # conditionally remove. but this
    # should not remove a middle  a.b.c.
    # 1.2ubuntu ->  1.2
    if [[ $VERSION =~ "^([[:digit:]]+)\\.([[:digit:]]+)([^.[:digit:]].*)$" ]]
       #                                                 ^??
    then
        if [ -n ${DEBUG-} ]; then
            cecho red "drop_verbal_suffix: Discarding $match[3] from the $VERSION";
        fi
        VERSION="$match[1].$match[2]"
    fi
}


# I want to detect a current git tag on HEAD, to not recreate it.
# return 1 if no such tag exists.
# return 0 & set the following variables if successul:
# VERSION
# DISTRIBUTION
# GIT_OFFSET
get_current_tag()
{
    if ! description=$(git describe --tags)
    then
        # are there any tags at all:
        if git tag -l |grep . > /dev/null;
        then
            cecho red "not _past_ Git tag. But other tags present"
            # fixme:
            if [ $FORCE != "y" ] # ???
            then
                exit 1
            fi
        else
            # fake values.
            VERSION=
            DISTRIBUTION=
            # GIT_OFFSET=$match[3]
            return 1
        fi
    else

        # 2 possibilities:
        # Either only the tag (possibly name/version),
        # or name/version-offset-g{hash} eg.  release|debian/3.4-2568-g59abc
        if [[ $description =~ "^(.*)/(.*)-([[:digit:]]+)-g[[:alnum:]]*$" ]]
        then
            DISTRIBUTION=$match[1]
            VERSION=$match[2]
            GIT_OFFSET=$match[3]
            # ${${description%-g*}#*-}

        elif [[ $description =~ "^(.*)/(.*)$" ]]
        then
            DISTRIBUTION=$match[1]
            VERSION=$match[2]
            #VERSION=${description#*/}
            #DISTRIBUTION=${description%/*}
        else
            echo "Found a non-release git tag: $description. So ignoring it." >&2
            return 1
        fi
    fi

    if [ -n "${DEBUG-}" ]; then
        cecho yellow "version: $VERSION git-offset: ${GIT_OFFSET:-} distro: $DISTRIBUTION" >&2
    fi
}


# decide, whether debian/changelog needs a new `section'
# todo: in-place if "git status" says clean
# keep changelog out:
# create it in a hook!

# for release: --git-builder /usr/bin/git-pbuilder
# dubious:
# todo: but, maybe it WAS committed in the last commit & nothing has changed!

# Return 0 iff last Changelog item is not commited?
# ENV: $FORCE
changelog_needs_new_section() {
    type=$1
    local FILE="debian/changelog"

    if [[ ${FORCE-n} = "y" ]]; then
        return 0
    elif git status --porcelain $FILE |grep --silent '^ M'; then
        # it's modified already.
        cecho yellow "$FILE is dirty"
        # mmc: for release this is 0, for snap it's 1....
        if [ $type = "release" ]; then
            return 0;
        else
            return 1;
        fi
    elif [ $(git log --pretty=%P -n 1 |wc -w) -gt 1 ]
    then
        cecho yellow "$FILE is clean but now we Merged and merge commits need specia attention"
        return 0

    elif ! git diff HEAD~1 --name-status $FILE | grep '^[AM]' > /dev/null
    then
        cecho yellow "$FILE was not updated during the last commit"
        return 0

    elif git status --porcelain  |grep --silent '^ M'; then
        # fixme!  something changed, (but _not_ debian/changelog)
        return 1
    elif git diff --name-only HEAD~1 | grep $FILE; then
        # so nothing changed, was it changed in the previous commit?
        return 1;
    else
        return 0
    fi
}


# Note: maybe a comitted debian/changelog has a higher
# version n. which was not released with a tag.

# Increase the VERSION, and compare with the one in debian/changelog.
# Make sure it's bigger than that.
# private/static
function _get_new_version()
{
    local step=$1

    increase_version -r $step
    local git_version=$VERSION
    # git_distro=$DISTRIBUTION

    # fixme: why? increase_version only rewrote VERSION!

    # This should be from
    # (sets DISTRIBUTION, VERSION)
    load_distr_version_from_changelog
    # drop_verbal_suffix

    if dpkg --compare-versions $VERSION lt $git_version;
    then
        # so this is expected, and here we `return' to the calculated VERSION value.
        # not very nice.
        # increase_version $step
        VERSION=$git_version
        # so the changelog contains a higher
        # version. git-dch would notice it.
        #
        # So, increase more.
    fi

    info "new version is $DISTRIBUTION $VERSION"
}


function git_reset_changelog()
{
    local FILE=debian/changelog
    # todo: if modified, reset it. Saving a copy.
    # that copy will be then removed, at the end.
    # This, because snap creates sections, which
    # we don't want here.
    if git status --porcelain $FILE| grep '^[M ]M' > /dev/null;
    then
        mv $FILE $FILE.pre-release
        git checkout $FILE
    fi
}

# That obviously implies the Git-Tag, then, on the new commit.
# input: USER_VERSION, USER_DISTRIBUTION, DCH_OPTIONS
# modifies/output: VERSION, DISTRIBUTION,
function generate_commit_changelog()
{
    local step=$1
    if [ -n "${USER_VERSION:-}" ]
    then
        echo "overriding the version, as requested" >&2
        VERSION=${USER_VERSION}
    else
        # fixme: here we need to increase (& hence parse) the VERSION:
        _get_new_version $step
        #echo "Starting a new version $VERSION."
        #echo "Could have been explicitely specified with the -v option.">&2
        # no need to echo... the user will see it?
    fi

    [[ -n $USER_DISTRIBUTION ]] && DISTRIBUTION=$USER_DISTRIBUTION

    set -x
    git_reset_changelog

    local gbp_version=$(gbp buildpackage --version|cut -d ' '  -f 2)
    if dpkg --compare-versions $gbp_version gt 0.6; then
        # old did not support it.
        if [ -n "$DISTRIBUTION" ]; then
            DCH_OPTIONS+=(--distribution $DISTRIBUTION)
        fi
    fi

    gbp dch $DCH_OPTIONS --release --auto --new-version="$VERSION"

    # Do the commit:

    # fixme: part of git_reset_changelog !
    rm -f debian/changelog.pre-release
    set +x
    if git status --porcelain debian/changelog| grep '^[M ]M' > /dev/null;
    then
        git add debian/changelog;
        # todo: "release $VERSION"
        git commit -m "release"
        GITSHA=$(git rev-list --max-count=1 HEAD)
    # else what to do?
    fi
}

# Using external tools, parse "debian/changelog"
# and set: DISTRIBUTION, VERSION
load_distr_version_from_changelog()
{
    local FILE="debian/changelog"
    DISTRIBUTION=$(deb-pkg-distribution $FILE)
    VERSION=$(deb-pkg-version $FILE)
}


# If the author of previous release was not me, just add the suffix "maruska",
my_own_project()
{
    expr match "$(deb-pkg-maintainer debian/control)" ".*maruska.*" >/dev/null
}


# rewrites the $VERSION variable:
# increase the first of last numeric value.

# fixme: why does `release' use generate_commit_changelog while snap increase_version?
# generate_commit_changelog -> _get_new_version -> increase_version
increase_version()
{
    local release="n"
    if [[ $1 = "-r" ]]; then
        release=y
        shift
    fi

    local step=$1
    set -x
    # fixme: it can be: (from git)
    # a.b.c~git-offset

    # this is for release!
    if [[ $release = y ]] && my_own_project; then
        # after a snapshot version: x.y.z~snapshot
        # just drop the ~suffix:
        if [[ $VERSION =~ "(.*)~.*$" ]]
        then
            VERSION="$match[1]"
        fi
        return
    fi

    local prefix
    local major
    local middle
    local minor
    local tail
    # non-digit(digit).*non-digit(digit*)non-digit*
    #           major     middle  minor  tail
    if [[ "$VERSION"  =~ '([^0-9]*)([0-9]+)(.*[^0-9])([0-9]+)([^0-9]*)' ]];
    then
        prefix=$match[1]
        major=$match[2]
        middle=$match[3]
        minor=$match[4]
        tail=$match[5]
    else
        # major. minor the last number!
        prefix=""
        major=${VERSION%%.*} # longest matching is dropped. So this is beginning up to first "."
        minor=${VERSION##*.} # longest dropped ->  from the last "." to the end.

        tail=.${VERSION#*.} # shortest at the beginning is dropped.
        middle=${tail%.*}
    fi
    cecho red "increasing version($prefix, $major, $middle, $minor, $tail) by step: $step"

    if my_own_project;
    then
        if [ $step = "major" ]
        then
            if ! major=$(expr $major + 1);
            then
                echo "cannot increase $VERSION"
                exit 1
            fi
            minor=0
        else
            if ! minor=$(expr $minor + 1)
            then
                echo "cannot increase $VERSION by minor"
                exit 1
            fi
        fi
        VERSION="$prefix$major${middle}$minor$tail"
    else
        VERSION="$prefix$major$middle${minor}-maruska"
    fi
}


# this is a toggle between ssh-agent implementation in GPG, and the native SSH-agent.
ssh_works=y


# GNU-GPG
restart_gpg()
{
    cecho red restarting >&2
    if [ $ssh_works = y ]; then
        ssh_option=
    else
        ssh_option="--enable-ssh-support"
    fi
    gpg-agent --daemon $ssh_option --default-cache-ttl 1800 \
        --write-env-file "${HOME}/.gpg-agent-info" >! ~/.gpg-agent-info
}

# (re-)load the SHELL code generated by gpg-agent.
# But ignore the SSH* related values -- I prefer to use the ssh-agent?
load_config()
{
    if [ $ssh_works = y ]; then
        BKP_SSH_AUTH_SOCK=$SSH_AUTH_SOCK
        BKP_SSH_AGENT_PID=${SSH_AGENT_PID-}
    fi

    source ~/.gpg-agent-info
    # since 5/2012 it does the export!
    export GPG_AGENT_INFO

    if [ $ssh_works = y ]; then
        # restore
        SSH_AUTH_SOCK=$BKP_SSH_AUTH_SOCK
        SSH_AGENT_PID=$BKP_SSH_AGENT_PID
    else
        export SSH_AUTH_SOCK
        export SSH_AGENT_PID
    fi
    # but then this, makes it the main one:
    # which promises USer (X window connection is best)
}


# if the gpg agent does not answer anymore, start a new one, and source the SHELL values.
check_start_gnupg()
{
    if ! gpg-connect-agent -q '/bye' || [ $(gpg-connect-agent '/echo  ahoj' '/bye') != "ahoj" ]
    then
        cecho yellow "Have to restart gpg" >&2
        restart_gpg
        load_config
    fi

    if gpg-connect-agent -q '/bye' || [ $(gpg-connect-agent '/echo  ahoj' '/bye') != "ahoj" ]
    then
        cecho green "gpg is ok on ${GPG_AGENT_INFO-}" >&2
    fi

    export GPG_TTY=$(tty)
}
