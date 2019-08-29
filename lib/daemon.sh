## \brief Provide functions to ease creation of daemon scripts.
## \desc Simple consumers:
##
## Multiple consumers can consume the same directory.
## Each time a consumer wants to process a file, it tries to lock it.
## To lock it, it tries to create a directory named after the sha256 sum of
## the file name (file being a regular file or a directory).
## If the lock fails, it means the file is being processed by another consumer,
## and the consumer continue to the next file.
## If the lock succeeds, the consumer process the file, move the file,
## and then remove the lock.
## If all files in the directory are locked, consumers wait a certain amount of
## time before trying again to process files.
## If the directory is empty, consumers wait a certain amount of time before
## listing it again.
##
## Chained-consumers:
##
## Multiple directories can each be watched by several consumers (note: a
## consumer consumes one and only one directory). The processed files transit
## from one directory to another, until they finally land in a not-watched
## directory. In each directory, they are processed accordingly to what the
## consumers for this directory are doing (example: filter video files ->
## extract audio -> reencode to specific format -> normalize to N decibels ->
## move to final music folder).
## For a particular directory, consumers behave exactly like simple consumers,
## except for the following:
##
## In addition to setting a lock for the current directory
## when processing a file, consumers also set a lock (with the
## potential post-process name of the file) for the next directory in the
## chain. This is done to avoid files being processed by the next consumers
## before the files are completely moved to the next directory.

shellm source shellm/loop


## \function sha STRING
## \function-brief Compute sha256sum of string.
## \function-argument STRING String to compute sum for.
sha() {
  shasum | cut -d' ' -f1
}

## \function daemon-lock NAME [DIR]
## \function-brief Lock the given item thanks to its name.
## \function-argument NAME Name of the item to lock.
## \function-argument DIR Directory in which to create the lock (default to data).
daemon-lock() {
  local sum
  sum="$(sha <<<"$1")"
  echo "daemon-lock: ${sum}"
  mkdir "${__daemon_datadir}/${sum}"
}

## \function daemon-unlock NAME [DIR]
## \function-brief Unlock the given item thanks to its name.
## \function-argument NAME Name of the item to unlock.
## \function-argument DIR Directory in which to remove the lock (default to data).
daemon-unlock() {
  local sum
  sum="$(sha <<<"$1")"
  echo "daemon-unlock: ${sum}"
  rm -rf "${__daemon_datadir:?}/${sum}" 2>/dev/null
}

## \function daemon-locked FILEPATH
## \function-brief Test if NAME is locked.
## \function-argument NAME Name of the item to test.
## \function-argument DIR Directory in which to check the lock (default to data).
daemon-locked() {
  [ -d "${__daemon_datadir}/$(sha <<<"$1")" ]
}

## \function daemon-unlocked NAME [DIR]
## \function-brief Test if NAME is unlocked.
## \function-argument NAME Name of the item to test.
## \function-argument DIR Directory in which to check the lock (default to data).
daemon-unlocked() {
  ! daemon-locked "$@"
}

## \function daemon-send SOURCE TARGET
## \function-brief Lock then move each given file to watched directory of DAEMON.
## \function-argument SOURCE Absolute or relative filepath to send.
## \function-argument TARGET Target destination (absolute directory or file path).
daemon-send() {
  declare -a sources
  local source target final_target

  while [ $# -ne 1 ]; do
    sources+=("$1")
    shift
  done

  target="$1"

  echo "daemon-send: target ${target}"
  for source in "${sources[@]}"; do
    echo "daemon-send: source ${source}"

    if [ -d "${target}" ]; then
      final_target="${target%/}/${source##*/}"
    else
      final_target="${target}"
    fi
    echo "daemon-send: final target ${final_target}"

    echo "daemon-send: trying to acquire lock on final target"
    while ! daemon-lock "${final_target}"; do
      sleep "${WAIT_WHEN_SENDING:-1}"
    done

    echo "daemon-send: acquired lock on final target, sending"
    mv "${source}" "${final_target}"

    echo "daemon-send: unlocking final target"
    daemon-unlock "${final_target}"

  done
}

## \function daemon-empty [DIR]
## \function-brief Test if watched directory is empty.
## \function-argument DIR Directory to check (default to watched directory).
daemon-empty() {
  local dir="${1:-${WATCHED_DIR}}"
  # shellcheck disable=SC2164
  ( [ -d "${dir}" ] && cd "${dir}"; [ "$(echo .* ./*)" = ". .. ./*" ]; )
}

## \function daemon-process NAME
## \function-brief Consume (process) file identified by NAME. You must rewrite this function.
## \function-argument NAME Name of the file/folder to process.
daemon-process() {
  echo "consumer: (dummy) processing $1"
  sleep 3
}


daemon-parse-args() {
  ## \env WAIT_WHEN_EMPTY
  ## Time to wait (in seconds) when watched directory is empty.
  WAIT_WHEN_EMPTY=1

  ## \env WAIT_WHEN_LOCKED
  ## Time to wait (in seconds) when all items in watched directory are locked.
  WAIT_WHEN_LOCKED=1

  ## \env WAIT_WHEN_SENDING
  ## Time to wait (in seconds) when file being sent is locked.
  WAIT_WHEN_SENDING=1

  declare -ga REMAINING_ARGS

  while [ $# -ne 0 ]; do
    case $1 in
      # \option -w, -watch DIRECTORY
      # Directory to watch.
      -w|--watch) WATCHED_DIR="$2"; shift ;;
      # \option -E, --wait-when-empty SECONDS
      # Time to wait (in seconds) when watched directory is empty
      -E|--wait-when-empty) WAIT_WHEN_EMPTY="$2"; shift ;;
      # \option -L, --wait-when-locked SECONDS
      # Time to wait (in seconds) when item is locked
      -L|--wait-when-locked) WAIT_WHEN_LOCKED="$2"; shift ;;
      # \option -S, --wait-when-sending SECONDS
      # Time to wait (in seconds) when file being sent is locked.
      -S|--wait-when-sending) WAIT_WHEN_LOCKED="$2"; shift ;;

      *) REMAINING_ARGS+=("$1")
    esac
    shift
  done
}

daemon-start-processing() {
  local __daemon_datadir

  __daemon_datadir="/tmp/shellm_daemon/locks"
  mkdir -p "${__daemon_datadir}" &>/dev/null
  ## \env WATCHED_DIR
  ## Path to directory to consume.
  if [ ! -d "${WATCHED_DIR}" ]; then
    mkdir -p "${WATCHED_DIR}"
  fi

  local all_locked item loop_name

  loop_name="${0##*/}.$$"
  loop init "${loop_name}"
  # shellcheck disable=SC2064
  trap "loop stop '${loop_name}'" SIGINT

  while true; do
    loop control "${loop_name}" || break
    if ! daemon-empty "${WATCHED_DIR}"; then
      all_locked=true
      for item in "${WATCHED_DIR}"/*; do
        echo "${loop_name}: trying to acquire lock on ${item}"
        if daemon-lock "${item}"; then
          echo "${loop_name}: lock acquired on ${item}"
          all_locked=false
          echo "${loop_name}: processing ${item}"
          daemon-process "${item}"
          echo "${loop_name}: unlocking ${item}"
          daemon-unlock "${item}"
        fi
      done
      # shellcheck disable=SC2086
      ${all_locked} && sleep ${WAIT_WHEN_LOCKED}
    else
      # shellcheck disable=SC2086
      sleep ${WAIT_WHEN_EMPTY}
    fi
  done
}
