# stolen from http://codeinthehole.com/tips/tips-for-using-a-git-pre-commit-hook/
FILES_PATTERN='\.(ex|exs)(\..+)?$'
FORBIDDEN='IEx.pry'
git diff --cached --name-only | \
    grep -E $FILES_PATTERN | \
    GREP_COLOR='4;5;37;41' xargs grep --color --with-filename -n $FORBIDDEN && echo "COMMIT REJECTED Found \"$FORBIDDEN\" references. Please remove them before commiting" && exit 1
# end stolen code

mix format --check-formatted mix.exs "lib/**/*.{ex,exs}" "test/**/*.{ex,exs}"
