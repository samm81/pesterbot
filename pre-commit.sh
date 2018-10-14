#!/usr/bin/env bash
if test "$BASH" = "" || "$BASH" -uc "a=();true \"\${a[@]}\"" 2>/dev/null; then
	# Bash 4.4, Zsh
	set -euo pipefail
else
	# Bash 4.3 and older chokes on empty arrays with set -u.
	set -eo pipefail
fi
shopt -s nullglob globstar

# Use colors, but only if connected to a terminal, and that terminal supports them.
if which tput >/dev/null 2>&1; then
	ncolors=$(tput colors)
fi
[ -t 1 ] && [ -n "$ncolors" ] && [ "$ncolors" -ge 8 ]
has_colors=$?
RED="$( (( has_colors == 0 )) && tput setaf 1 || echo '' )"
GREEN="$( (( has_colors == 0 )) && tput setaf 2 || echo '' )"
YELLOW="$( (( has_colors == 0 )) && tput setaf 3 || echo '' )"
BLUE="$( (( has_colors == 0 )) && tput setaf 4 || echo '' )"
BOLD="$( (( has_colors == 0 )) && tput bold || echo '' )"
NORMAL="$( (( has_colors == 0 )) && tput sgr0 || echo '' )"

#set -o xtrace # set debugging flag, aka set -x

if git rev-parse --verify HEAD >/dev/null 2>&1
then
	against=HEAD
else
	# Initial commit: diff against an empty tree object
	against=4b825dc642cb6eb9a060e54bf8d69288fbee4904
fi

# If you want to allow non-ASCII filenames set this variable to true.
allownonascii=$(git config --bool hooks.allownonascii) || :

# Redirect output to stderr.
exec 1>&2

# Cross platform projects tend to avoid non-ASCII filenames; prevent
# them from being added to the repository. We exploit the fact that the
# printable range starts at the space character and ends with tilde.
if [ "$allownonascii" != "true" ] &&
	# Note that the use of brackets around a tr range is ok here, (it's
	# even required, for portability to Solaris 10's /usr/bin/tr), since
	# the square bracket bytes happen to fall in the designated range.
	test "$(git diff --cached --name-only --diff-filter=A -z $against |
	  LC_ALL=C tr -d '[ -~]\0' | wc -c)" != 0
then
	echo -n "${RED}"
	cat <<\EOF
Error: Attempt to add a non-ASCII file name.

This can cause problems if you want to work with people on other platforms.

To be portable it is advisable to rename the file.

If you know what you are doing you can disable this check using:

  git config hooks.allownonascii true
EOF
	echo -n "${NORMAL}"
	exit 1
fi

# stolen from http://codeinthehole.com/tips/tips-for-using-a-git-pre-commit-hook/
git stash -q --keep-index
./run-tests.sh || :
RESULT=$?
git stash pop -q
[ $RESULT -ne 0 ] && exit 1
exit 0
# end stolen code

# If there are whitespace errors, print the offending file names and fail.
exec git diff-index --check --cached $against --
