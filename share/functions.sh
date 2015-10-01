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
	    sanitize_version

	elif [[ $description =~ "^(.*)/(.*)$" ]]
	then
	    DISTRIBUTION=$match[1]
	    VERSION=$match[2]
	    #VERSION=${description#*/}
	    #DISTRIBUTION=${description%/*}
	else
	    echo "cannot find a git tag? wrong format of: $description" >&2
	    return 1
	fi
    fi

    if [ -n "${DEBUG-}" ]; then
	cecho yellow "version: $VERSION git-offset: ${GIT_OFFSET:-} distro: $DISTRIBUTION" >&2
    fi
}

# modifies the VERSION variable.
sanitize_version()
{
    # conditionally remove. but this
    # should not remove a middle  a.b.c.
    # 1.2ubuntu ->  1.2
    if [[ $VERSION =~ "^([[:digit:]]+)\\.([[:digit:]]+)([^.[:digit:]].*)$" ]]
	#                                                 ^??
    then
	VERSION="$match[1].$match[2]"
	if [ -n ${DEBUG-} ]; then
	    cecho red "Discarding $match[3] from the TAG";
	fi
    fi
}


load_distr_version_from_changelog()
{
    DISTRIBUTION=$(deb-pkg-distribution debian/changelog)
    VERSION=$(deb-pkg-version debian/changelog)
    sanitize_version
}

# in VERSION variable.
increase_version()
{
    local step=$1

    # it can be: (from git)
    # a.b.c~git-offset
    if [[ $VERSION =~ "(.*)~.*$" ]]
    then
	VERSION="$match[1]"
    fi
    major=${VERSION%%.*}
    minor=${VERSION##*.}

    tail=.${VERSION#*.}
    middle=${tail%.*}

    # echo "major=$major  minor=$minor"
    cecho red "increasing version by ($major, $middle, $minor)... $step"
    # if expr match ".-." $minor
    if expr match "$minor" ".-\(.\)";
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
