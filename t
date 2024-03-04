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

VERSION=0.3.0

TODOFILE="${HOME}/.config/.TODO"
[ -d "${HOME}/.config " ] && mkdir "${HOME}/.config"
[ -f "${TODOFILE}" ] || echo "[]" > "${TODOFILE}"

OPTIONS="hVad:lLn:m:ps:r:u:w:"


usage() {
    cat <<EOF
usage: t [options] [ID|DESCRIPTION]

The default action is to list ('-l') tasks. If only a positional
parameter is provided, if it is a number (ID{, the details of a single
task is shown (same as '-l ID'), if it is a string (DESCRIPTION), a new
task is added to the task list (same as '-a DESC').

Version: $VERSION

Options:
  -h              Print this help and exit.
  -V              Print version and exit.

  -a DESC         Add a new task.
  -d ID           Mark a task as done.
  -l [ID]         List all open tasks, or detail a single open task.
  -L [ID]         List all done tasks, or detail a silgle done task.
  -n ID           Add a note to task.
  -m ID           Modify a task.
                  Use toghether with any of '-w' and DESCRIPTION.
  -p              Purge all done tasks.
  -r ID           Remove a task.
  -s ORDER        Sort tasks by selected field. Valid options are:
                      due: Due date (defalt)
                      done: Done date (default for 'done tasks')
                      create: Creation date
                      description: Alphabetically by description
  -u ID           Mark task as undone.
  -w TIMESTAMP    When task is due (%Y-%m-%d [%H:%M])

EOF
}


check_deps() {
    type "$1" >/dev/null && return 0 || return 1
}


die() {
    >&2 echo $*
    exit 1 
}


check_no_error() {
    [ $? == 0 ] && die "$*"
}


check_error() {
    [ $? != 0 ] && die "$*"
}


update_tasks() {
    local tmpfile
    tmpfile="$(mktemp)"
    jq "$@" < "${TODOFILE}" > "${tmpfile}" && mv "${tmpfile}" "${TODOFILE}"
    RESULT=$?
    rm -f "${tmpfile}"
    return ${RESULT}
}


join_note() {
  local d=${1-} f=${2-}
  if shift 2; then
    printf %s "$f" "${@/#/$d}"
  fi
}


FUTURE_DATE="\"$(date --date "$(($(date +"%Y") + 100))-12-31" +"%Y-%m-%dT%H:%M:%SZ")\""
TODAY_DATE="\"$(date +"%Y-%m-%dT%H:%M:%SZ")\""
SORT_BY_DUE_DATE="map(._sort_date=if .due_date then .due_date else $FUTURE_DATE end) | sort_by(._sort_date)"
SORT_BY_DONE_DATE="sort_by(.done) | reverse"
SORT_BY_CREATION="map(._sort_date=if .creation_time then .creation_time else $TODAY_DATE end) | sort_by(._sort_date)"
SORT_BY_DESCRIPTION="sort_by(.description)"
SORT_OPEN_TASKS="${SORT_BY_DUE_DATE}"
SORT_DONE_TASKS="${SORT_BY_DONE_DATE}"
declare -A sort_opts
sort_opts=(
    ["create"]="${SORT_BY_CREATION}"
    ["done"]="${SORT_BY_DONE_DATE}"
    ["due"]="${SORT_BY_DUE_DATE}"
    ["desc"]="${SORT_BY_DESCRIPTION}"
)
SORT_ORDER="due"


SELECT_OPEN='map(select(.done | not))'
SELECT_DONE='map(select(.done))'
SELECT_BY_ID='.[$id - 1]'
SELECT_BY_DESCRIPTION='map(select(.description == $description)) | if length > 0 then map(.) else null end'
GET_DESCRIPTION_BY_ID="${SELECT_BY_ID}|.description"
AS_ENTRIES="to_entries | .[]"


add_note() {
    check_deps sed || die "Notes are not supported."

    local tmpfile task SET_NOTE note_data new_note
    tmpfile="$(mktemp --tmpdir "${USER}-t-XXXXXX")"
    task="$(jq -M --exit-status --argjson id "$1" "${SELECT_OPEN}|${sort_opts[${SORT_ORDER}]}|${GET_DESCRIPTION_BY_ID}" < "${TODOFILE}")"
    check_error "Task #${1} not open."
    IFS="," read -ra note_data <<< $(jq -crM --argjson id "$1" "${SELECT_BY_ID} | select(.note != null).note" < "${TODOFILE}" | sed -n -e "s/^\[\(.*\)\]$/\1/p")
    echo -e $(join_note "\n" "${note_data[@]}") | sed -e 's/^"\(.*\)"$/\1/' > "${tmpfile}"
    original_data="$(cat ${tmpfile})"
    check_deps "${EDITOR:-vim}" || die "No editor found. (Please set env var EDITOR.)"
    ${EDITOR:-vim} "${tmpfile}"
    if [ -n "$(diff - "${tmpfile}" <<<${original_data})" ]
    then
        mapfile -t note_data < "${tmpfile}"
        new_note="[\"$(join_note '", "' "${note_data[@]}")\"]"
        SET_NOTE='(.[] | select(.description == $task)).note |= $data'
        update_tasks --argjson task "${task}" --argjson data "${new_note}" "${SET_NOTE}"
        check_error "Failed to add note to #${1}"
        echo "Added note to: #${1}: ${task}"
    else
        echo "Note not changed."
    fi
    rm -f "${tmpfile}"
}


list() {
    local FORMAT FORMAT_DUE_DATE
    if [ -z "$1" ]
    then
        FORMAT='"\(.key + 1): \(.value.description) \(try (.value.due_date | fromdate | strftime("(due: %Y-%m-%d)")) catch "")"'
        jq -M "${SELECT_OPEN}|${sort_opts[${SORT_ORDER}]}|${AS_ENTRIES}|${FORMAT}" < "${TODOFILE}" | tr -d '"'
    else
        FORMAT_DUE_DATE='(.due_date = (try (.due_date | fromdate | strftime("%Y-%m-%d %H:%M")) catch null)) | del(..|nulls)'
        jq -C --argjson id "$1" "${SELECT_OPEN}|${sort_opts[${SORT_ORDER}]}|${SELECT_BY_ID} | ${FORMAT_DUE_DATE}" < "${TODOFILE}"
    fi
}


list_done() {
    local FORMAT
    FORMAT='"\(.key + 1): \(.value.description) (Completed: \(.value.done | fromdate | strftime("%Y-%m-%d %H:%M")))"'
    jq -M "${SELECT_DONE}|${sort_opts[${SORT_ORDER}]}|${AS_ENTRIES}|${FORMAT}" < "${TODOFILE}" | tr -d '"'
}


append() {
    jq --argjson description "\"$1\"" --exit-status "${SELECT_BY_DESCRIPTION}" < "${TODOFILE}" >/dev/null
    check_no_error "Task already exists."

    local creation changes
    declare -a changes
    if check_deps date
    then
        creation="$(jq 'fromdate | todate' <<< "\"$(date -Iseconds | cut -d- -f1-3)Z\"")"
        changes=("creation_time: $creation" "description: \"${1}\"")
    else
        changes=("description: \"${1}\"")
    fi
    [ -n "${DATE}" ] && changes+=("due_date: ${DATE}")

    update_tasks ". += [{$(join_note "," "${changes[@]}")}]"
    check_error "Failed to create task."
    echo "Created new task."
}


purge() {
    update_tasks "${SELECT_OPEN}"
    check_error "Failed to purge tasks."
    echo "Purged done tasks."
}


remove() {
    local task
    task="$(jq -M --exit-status --argjson id "$1" "${SELECT_OPEN}|${sort_opts[${SORT_ORDER}]}|${GET_DESCRIPTION_BY_ID}"  < "${TODOFILE}")"
    check_error "Task #${1} not open. Use 'purge' (-p) to remove all done tasks."

    update_tasks --argjson task "$task" --exit-status '. | map(select(.description == $task | not))'
    check_error "Failed to remove task: #${1}."
    echo "Removed task: #${1}: ${task}"
}


mark_done() {
    local task
    task="$(jq -M --exit-status --argjson id "$1" "${SELECT_OPEN}|${sort_opts[${SORT_ORDER}]}|${GET_DESCRIPTION_BY_ID}" < "${TODOFILE}")"
    check_error "Task #${1} not open."

    SET_TASK_DONE='(.[] | select(.description == $task)).done |= (now | localtime | todate)' 
    update_tasks --argjson task "${task}" "${SET_TASK_DONE}"
    check_error "Failed to complete task #${1}: ${task}"
    echo "Marked as done: #${1}: ${task}"
}


mark_undone() {
    local task
    task="$(jq -M --exit-status --argjson id "$1" "${SELECT_DONE}|${sort_opts[${SORT_ORDER}]}|${GET_DESCRIPTION_BY_ID}"  < "${TODOFILE}")"
    check_error "Task #${1} not done."

    SET_TASK_UNDONE='(.[] | select(.description == $task)).done |= false' 
    update_tasks --argjson task "${task}" "${SET_TASK_UNDONE}"
    check_error "Failed to reopen task: #${1}."
    echo "Marked as not done: #${1}: ${task}"
}


modify_task() {
    task_id="${1}"
    shift 1

    task="$(jq -M --argjson id "${task_id}" --exit-status "${SELECT_OPEN}|${sort_opts[${SORT_ORDER}]}|${GET_DESCRIPTION_BY_ID}" < "${TODOFILE}")"
    check_error "Task #${task_id} not open."

    local changes
    declare -a changes

    [ -n "${1}" ] && description="\"${1}\"" || description="${task}"
    changes="description: ${description}"

    [ -n "${DATE}" ] && changes+=("due_date: ${DATE}")

    update_tasks --argjson task "${task}" "(.[] | select(.description == \$task)) += {$(join_note "," "${changes[@]}")}"

    echo "Task ${task}:"
    jq --argjson task "${description}" "(.[] | select(.description == \$task))" < "${TODOFILE}"
}

ID=''
CMD=''


while getopts "${OPTIONS}" opt
do
    case "${opt}" in
        "a") CMD='append' ;;
        "d") CMD='mark_done' ; ID="${OPTARG}";;
        "l") CMD='list' ;;
        "L") CMD='list_done' ; SORT_ORDER="done" ;;
        "n") CMD='add_note' ; ID="${OPTARG}" ;;
        "m") CMD='modify_task' ; ID="${OPTARG}" ;;
        "p") CMD='purge' ;;
        "r") CMD='remove' ; ID="${OPTARG}" ;;
        "s")
            case "${OPTARG}" in
                "due"|"done"|"desc"|"create") SORT_ORDER="${OPTARG}" ;;
                *) die "Invalid sort order: ${OPTARG}" ;;
            esac ;;
        "u") CMD='mark_undone' ; SORT_ORDER="done" ; ID="${OPTARG}" ;;
        "w") DATE="$( (echo "\"${OPTARG}\"" | jq 'try strptime("%Y-%m-%d %H:%M") catch (split("\"")[1] | strptime("%Y-%m-%d")) | todate') || die "Invalid date")";;
        "h") usage && exit 0 ;;
        "V") echo "t version $VERSION" && exit 0;;
        *) usage && exit 1 ;;
    esac
done

SORT_ORDER="${SORT_ORDER:-due}"

shift $(( OPTIND - 1 ))

ARG="$*"

IS_NUM=$(( echo -n "${ARG}" | grep -Eq '[^0-9]' ) && echo NO || echo YES)

if [ -z "${CMD}" ] && [ "${IS_NUM}" == "YES" ]
then
    CMD='list'
else
    [ -z "${CMD}" ] && CMD='append'
fi 

${CMD} $ID "${ARG}"
