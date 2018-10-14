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

# stolen from http://codeinthehole.com/tips/tips-for-using-a-git-pre-commit-hook/
FILES_PATTERN='\.(ex|exs)(\..+)?$'
FORBIDDEN='IEx.pry'
git diff --cached --name-only | \
    grep -E "$FILES_PATTERN" | \
    GREP_COLOR='4;5;37;41' xargs grep --color --with-filename -n $FORBIDDEN && echo "COMMIT REJECTED Found \"$FORBIDDEN\" references. Please remove them before commiting" && exit 1
# end stolen code

mix format --check-formatted mix.exs "lib/**/*.{ex,exs}" "test/**/*.{ex,exs}" && true
if [ $? -ne 0 ]; then
    echo "${RED}${BOLD}Please run ${NORMAL}${BLUE}mix format${BOLD}${RED} on unformatted files.${NORMAL}"
    exit 1
fi
exit 0
