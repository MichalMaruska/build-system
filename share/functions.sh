#! /usr/bin/zsh

# Common functions for the scripts



# I want to detect a current tag & reuse it, ie. not recreate it.

## return 0 & set the variables if successul.
# variables:

# VERSION
# DISTRO
# GIT_OFFSET
get_current_tag()
{
    set +e
# git describe --all -> HEAD or master.
# I only want tags
    description=$(git describe --tags)
    git_status=$?
    set -e

    # if no tags at all -> exit, or ?
    if [ $git_status -ne 0 ]
    then
	if git tag -l |grep .;
	then
	    cecho red "not _past_ Git tag. But other tags present"
	    if [ $FORCE != "y" ]
	    then
		:
	    else
		exit 1
	    fi
	else
	    return 1
	fi
    else

    # 2 possibilities:
    # Either only the tag (possibly name/version),
    # or name/version-offset-g{hash}
    #
	if [[ $description =~ "^(.*)/(.*)-([[:digit:]]+)-g[[:alnum:]]*$" ]]
	then
	    DISTRO=$match[1]
	    VERSION=$match[2]
	    GIT_OFFSET=$match[3]
	    # ${${description%-g*}#*-}

	elif [[ $description =~ "^(.*)/(.*)$" ]]
	then
	    DISTRO=$match[1]
	    VERSION=$match[2]
	    #VERSION=${description#*/}
	    #DISTRO=${description%/*}
	else
	    exit
	fi
    fi

    cecho yellow $VERSION ${GIT_OFFSET:-} $DISTRO >&2
}

