#!/bin/bash

# Copyright (c) 2024 Rafael Guterres Jeffman
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice (including the next
# paragraph) shall be included in all copies or substantial portions of the
# Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
# THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.


TODOFILE="${HOME}/.config/.TODO"
[ -d "${HOME}/.config " ] && mkdir "${HOME}/.config"
[ -f "${TODOFILE}" ] || echo "[]" > "${TODOFILE}"

OPTIONS="had:lLpr:u:w:"

usage() {
    cat <<EOF
usage: t [-l [ID]] [-d|-r|-u ID] [-w TIMESTAMP] [-a DESCRIPTION] [ID_OR_DESCRIPTION]

The default action is to list ('-l') tasks. If only a positional
parameter is provided, if it is a number, the details of a task
is shown ('-l ID'), if it is a string, a new task is added to the
task list.

Options:
      -a DESC        Add a new task
      -d ID          Mark a task as done
      -l [ID]        List all tasks, or detail a single task
      -L             List all done tasks
      -p             Purge all done tasks.
      -r ID          Remove a task
      -u ID          Mark task as undone
      -w TIMESTAMP   When task is due (%Y-%m-%d [%H:%M])
EOF
}

die() {
    >&2 echo $*
    exit 1 
}


SORT_BY_DUE_DATE="sort_by(.due_date) | reverse"

list() {
    if [ -z "$1" ]
    then
        jq -M 'map(select(.done != true)) | '"${SORT_BY_DUE_DATE}"' | to_entries | .[] | "\(.key): \(.value.description) (\(try (.value.due_date | fromdate | strftime("%Y-%m-%d")) catch "no date"))"' < "${TODOFILE}" | tr -d '"'
    else
        QUERY='| (.due_date = (try (.due_date | fromdate | strftime("%Y-%m-%d %H:%M")) catch null)) | del(..|nulls)'
        jq -C ".[$1] $QUERY" < "${TODOFILE}"
    fi
}


list_done() {
    jq -M '. | map(select(.done == true)) | to_entries | .[] | "\(.key): \(.value.description)"'  < "${TODOFILE}" | tr -d '"'
}


append() {
    if jq --argjson task "\"$1\"" --exit-status '. | map(select(.description == $task)) | if length > 0 then map(.) else null end' < "${TODOFILE}" >/dev/null
    then
        echo "Task already exists."
        return
    fi

    tmpfile="$(mktemp)"

    if [ -z "${DATE}" ]
    then
        jq --argjson task "\"$1\"" '. += [{description:$task, done: false}]' < "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}" && echo "Created new task."
    else
        jq --argjson task "\"$1\"" --argjson date "$DATE" '. += [{description:$task, done: false, due_date: $date}]' < "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}" && echo "Created new task."
    fi
}


purge() {
    tmpfile="$(mktemp)"
    jq '. |= map(select(.done != true))' < "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}"
    echo "Purged done tasks."
}


remove() {
    task="$(jq -M --exit-status --argjson id "$1" '. | map(select(.done != true)) | .[$id].description'  < "${TODOFILE}")"

    if [ $? != 0 ] 
    then
        echo "Task #${1} not open. Use 'purge' (-p) to remove all done tasks."
        return
    fi

    tmpfile="$(mktemp)"
    jq --argjson task "$task" --exit-status '. | map(select(.description == $task | not))' "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}"
    echo "Removed task: #${1}: ${task}"
}


mark_done() {
    task="$(jq -M --exit-status --argjson id "$1" '. | map(select(.done != true)) | .[$id].description'  < "${TODOFILE}")"

    if [ $? != 0 ] 
    then
        echo "Task #${1} not open."
        return
    fi

    tmpfile="$(mktemp)"
    jq --argjson task "${task}" '(.[] | select(.description == $task)).done |= true' < "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}"
    echo "Marked done: #${1}: ${task}"
}


mark_undone() {
    task="$(jq -M --exit-status --argjson id "$1" '. | map(select(.done == true)) | .[$id].description'  < "${TODOFILE}")"

    if [ $? != 0 ] 
    then
        echo "Task #${1} not done."
        return
    fi

    tmpfile="$(mktemp)"
    jq --argjson task "${task}" '(.[] | select(.description == $task)).done |= false' < "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}"
    echo "Marked done: #${1}: ${task}"
}


CMD=''

while getopts "${OPTIONS}" opt
do
    case "${opt}" in
        "a") CMD='append' ;;
        "d") CMD='mark_done' ; ARG="${OPTARG}";;
        "l") CMD='list' ;;
        "L") CMD='list_done' ;;
        "p") CMD='purge' ;;
        "r") CMD='remove' ; ARG="${OPTARG}" ;;
        "u") CMD='mark_undone' ; ARG="${OPTARG}" ;;
        "w") DATE="$(echo "\"${OPTARG}\"" | jq 'try strptime("%Y-%m-%d %H:%M") catch (split("\"")[1] | strptime("%Y-%m-%d")) | todate')" ;;
        "h") usage && exit 0 ;;
        *) usage && exit 1 ;;
    esac
done

shift $(( OPTIND - 1))

ARG="${ARG:-$*}"

IS_NUM=$(( echo -n "${ARG}" | grep -Eq '[^0-9]' ) && echo NO || echo YES)

if [ -z "${CMD}" ] && [ "${IS_NUM}" == "YES" ]
then
    CMD='list'
else
    [ -z "${CMD}" ] && CMD='append'
fi 

${CMD} "${ARG}"

