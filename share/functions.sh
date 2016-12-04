#! /usr/bin/zsh

# Common functions for the scripts

check_getopt()
{
    if getopt -T; then # should test (( $? = -4 ))
        echo "incompatible  getopt(1) installed. Abort"
        exit -1
    fi
}

possibly_trace()
{
    if [ -n "${DEBUG-}" ]; then
        #cecho blue setting DEBUGGING on >&2
        #setopt XTRACE
        #unsetopt LOCAL_OPTIONS
        echo "set -x"
    fi
}


# modifies the VERSION variable.
# Drops the letter-suffix, after 2-number version  NN.MMsuffix
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


# I want to detect a current git tag & reuse it, ie. not recreate it.

## return 0 & set the variables if successul.
# variables:

# VERSION
# DISTRIBUTION
# GIT_OFFSET
get_current_tag()
{
    if ! description=$(git describe --tags)
    then
        if git tag -l |grep . > /dev/null;
        then
            cecho red "not _past_ Git tag. But other tags present"
            # fixme:
            if [ $FORCE != "y" ]
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
        # or name/version-offset-g{hash}
        #
        if [[ $description =~ "^(.*)/(.*)-([[:digit:]]+)-g[[:alnum:]]*$" ]]
        then
            DISTRIBUTION=$match[1]
            VERSION=$match[2]
            GIT_OFFSET=$match[3]
            # ${${description%-g*}#*-}
            drop_verbal_suffix

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

# Return 0 iff last Changelog item is UNRELEASED.
# ENV: $FORCE
changelog_needs_new_section() {
    type=$1
    local FILE="debian/changelog"

    if [ ${FORCE-n} = "y" ]; then
        return 0
    elif git status --porcelain $FILE |grep --silent '^ M'; then
        # it's modified already.
        cecho yellow "$FILE is dirty, so let's review it"
        # mmc: for release this is 0, for snap it's 1....
        if [ $type = "release" ]; then
            return 0;
        else
            return 1;
        fi
    elif [ $(git log --pretty=%P -n 1 |wc -w) -gt 1 ]
    then
        cecho yellow "$FILE is clean but now we Merged"
        return 0

    elif ! git diff HEAD~1 --name-status $FILE | grep '^M' > /dev/null
    then
        cecho yellow "$FILE was not updated during the last commit"
        return 0

    elif git status --porcelain  |grep --silent '^ M'; then
        # fixme!  something changed, (but _not_ debian/changelog)
        return 0
    elif git diff --name-only HEAD~1 | grep $FILE; then
        # so nothing changed, was it changed in the previous commit?
        return 1;
    else
        return 0
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

# rewrites the @VERSION env-variable, which was taken from ? (changelog or git tag?)
#
# todo: if suffix is "maruska" then I want to keep it.
# if the author of previous was not me, I want to suffix "maruska".
increase_version()
{
    local step=$1

    # it can be: (from git)
    # a.b.c~git-offset
    if [[ $VERSION =~ "(.*)~.*$" ]]
    then
        VERSION="$match[1]"
    fi
    major=${VERSION%%.*} # longest matching is dropped. So this is beginning up to first "."
    minor=${VERSION##*.} # longest dropped ->  from the last "." to the end.

    tail=.${VERSION#*.} # shortest at the beginning is dropped.
    middle=${tail%.*}

    # echo "major=$major  minor=$minor"
    cecho red "increasing version($major, $middle, $minor) by step: $step"
    # if expr match ".-." $minor
    if expr match "$minor" ".\+-.\+" >/dev/null
    then
        local postfix=maruska
        VERSION="$major${middle-.${middle}}.$minor"$postfix
    else
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

        VERSION="$major${middle-.${middle}}.$minor"
    fi
}

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
