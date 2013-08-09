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
	cecho blue setting DEBUGGING on >&2
	setopt XTRACE
	unsetopt LOCAL_OPTIONS
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
#    set +e
# git describe --all -> HEAD or master.
# I only want tags
    description=$(git describe --tags)
    git_status=$?
#    set -e

    # if no tags at all -> exit, or ?
    if [ $git_status -ne 0 ]
    then
	if git tag -l |grep . > /dev/null;
	then
	    cecho red "not _past_ Git tag. But other tags present"
	    if [ $FORCE != "y" ]
	    then
		:
	    else
		exit 1
	    fi
	else
	    # fake values.
	    VERSION=
	    DISTRIBUTION=
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
	    if [[ $VERSION =~ "^([[:digit:]]+)\\.([[:digit:]]+)([^[:digit:]].*)$" ]]
	    then
		VERSION="$match[1].$match[2]"
		if [ -n ${DEBUG-} ]; then
		    cecho red "Discarding $match[3] from the TAG";
		fi
	    fi

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

load_distr_version_from_changelog()
{
    DISTRIBUTION=$(deb-pkg-distribution debian/changelog)
    VERSION=$(deb-pkg-version debian/changelog)

    # conditionally remove. but this
    # should not remove a middle  a.b.c.
    # 1.2ubuntu ->  1.2
    if [[ $VERSION =~ "^([[:digit:]]+)\\.([[:digit:]]+)([^.[:digit:]].*)$" ]]
    then
	VERSION="$match[1].$match[2]"
	cecho red "Discarding $match[3]"
    fi
}


# in VERSION variable.
increase_version()
{
    step=$1

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
    cecho red "increasing version by $step"
    if [ step = "major" ]
    then
	major=$(expr $major + 1)
	minor=0
    else
	minor=$(expr $minor + 1)
    fi

    VERSION="$major${middle-.${middle}}.$minor"
}
