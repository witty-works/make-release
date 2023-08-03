#!/bin/bash

set -e;

VERSION_REGEXP='([0-9]+)\.([0-9]+)\.([0-9]+)\.?([0-9]+)?';

VERSION_FILENAMES=$(sed -n '1p' make-release)
SENTRY_ORG=$(sed -n '2p' make-release)
SENTRY_SLUG=$(sed -n '3p' make-release)
BUILD_COMMAND=$(sed -n '4p' make-release)
BUILD_PATH=$(sed -n '5p' make-release)

Help()
{
   # Display Help
   echo "Make a release."
   echo
   echo "Syntax: make-release.sh [-h] [major|minor|patch|hotfix|rc|finish|finalize]"
   echo "options:"
   echo "-h   Output the help information"
   echo
}

echo "Updating version files: $VERSION_FILENAMES";

if [ ! -z "$SENTRY_ORG" ]
then
    if [ ! -z "$SENTRY_SLUG" ]
    then
            echo "Updating sentry release for project '$SENTRY_SLUG' on '$SENTRY_ORG' organization.";

            if [ ! -z "$BUILD_COMMAND" ]
            then
                if [ ! -z "$BUILD_PATH" ]
                then
                        echo "Generating sourcemaps after building '$BUILD_COMMAND' into '$BUILD_PATH'.";
                fi
            elif [ ! -z "$BUILD_PATH" ]
            then
                echo "Please either add a build command into the 4th line or remove the build path '$BUILD_PATH' from the 5th line.";

                exit;
            else
                echo "Not updating sourcemaps to sentry since there is no build command and build path set.";
            fi

    fi
elif [ ! -z "$SENTRY_SLUG" ]
then
    echo "Please either add a sentry org into the 2nd line or remove the sentry project '$SENTRY_SLUG' from the 3rd line.";

    exit;
else
    echo "Not updating sentry since there is no sentry organization set.";
fi

while getopts "hr:" opt; do
    case ${opt} in
    h )
        Help
        exit 1
        ;;
    esac
done

case $1 in
    major|minor|patch|hotfix|rc)
        MODE=$1;
        echo "Preparing '$MODE' updating dev/main";
        git checkout dev;
        git pull --rebase;
        git checkout main;
        git pull --rebase;

        PREV_VERSION=$(git tag | head -n 1);

        REGEXP="^$VERSION_REGEXP$";
        if [[ ! $PREV_VERSION =~ $REGEXP ]];
        then
            echo "Previous version should be in the format x.y.z and not '$PREV_VERSION'.";

            exit;
        fi

        declare -i MAJOR;
        declare -i MINOR;
        declare -i PATCH;
        declare -i RC;

        case $MODE in
            major)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]}+1;
                MINOR=0;
                PATCH=0;
            ;;
            minor)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]}+1;
                PATCH=0;
            ;;
            patch)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]};
                PATCH=${BASH_REMATCH[3]}+1;
            ;;
            hotfix)
                TYPE='hotfix';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]};
                PATCH=${BASH_REMATCH[3]}+1;
            ;;
            rc)
                TYPE='release';
                MAJOR=${BASH_REMATCH[1]};
                MINOR=${BASH_REMATCH[2]};
                PATCH=${BASH_REMATCH[3]};
                RC=${BASH_REMATCH[4]}+1;
            ;;
        esac

        VERSION="$MAJOR.$MINOR.$PATCH";

        if [ ! -z "$RC" ]
        then
            VERSION="$VERSION.$RC"
        fi

        set -x

        git flow $TYPE start $VERSION;

        set +x
        if [ ! -z "$SENTRY_SLUG" ]
        then
            set -x
            sentry-cli releases -o $SENTRY_ORG new -p $SENTRY_SLUG $VERSION;
            set +x
        fi
        set -x

        # hyphen (-) is set as delimiter
        IFS=','

        # str is read into an array as tokens separated by IFS
        read -ra values <<< "$VERSION_FILENAMES"

        #echo each of the value to output
        for VERSION_FILENAME in "${values[@]}"; do
            sed "s/$PREV_VERSION/$VERSION/" $VERSION_FILENAME > "${VERSION_FILENAME}.bak"
            mv "${VERSION_FILENAME}.bak" $VERSION_FILENAME
        done

        # reset IFS to default value
        IFS=' '
    ;;

    finish)
        BRANCH=$(git branch --show-current);
        REGEXP="^(release|hotfix)/($VERSION_REGEXP)+$";

        if [[ ! $BRANCH =~ $REGEXP ]];
        then
            echo "Please make sure you are currently on release or hotfix branch, ie. a branch named 'release|hotfix/x.y.z[.RC]' f.e. release/1.22.3";

            exit;
        fi

        TYPE=${BASH_REMATCH[1]};
        VERSION=${BASH_REMATCH[2]};

        if [ ! -z "$BUILD_COMMAND" ]
        then
            set -x
            eval "$BUILD_COMMAND"
            sentry-cli sourcemaps inject --org $SENTRY_ORG --project $SENTRY_SLUG $BUILD_PATH
            sentry-cli sourcemaps upload --org $SENTRY_ORG --project $SENTRY_SLUG $BUILD_PATH --release $VERSION
            set +x
        fi

        set -x

        git flow $TYPE finish $VERSION;
    ;;

    finalize)
        VERSION=$(git tag | head -n 1);
        PREV_VERSION=$(git tag | head -n 2 | tail -1);

        set -x

        git push origin main dev --tags;

        set +x
        if [ ! -z "$SENTRY_SLUG" ]
        then
            set -x
            sentry-cli releases -o $SENTRY_ORG finalize $VERSION;
            sentry-cli releases -o $SENTRY_ORG set-commits $VERSION --commit "$SENTRY_ORG/$SENTRY_SLUG@$PREV_VERSION..$VERSION";
            set +x
        fi
    ;;

    *)
        Help
   ;;
esac
