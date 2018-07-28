shellm-source core/init/data.sh

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
## Multiple directories can each be consumed by several consumers (note: a
## consumer consumes one and only one directory). The processed files transit
## from one directory to another, until they finally land in a not-consumed
## directory. In each directory, they are processed accordingly to what the
## consumers for this directory are doing (example: filter video files ->
## extract audio -> reencode to specific format -> normalize to N decibels ->
## move to final music folder)
## For a particular directory, consumers behave exactly like simple consumers,
## except for the following:
##
##     In addition to setting a lock for the current
##     directory when processing a file, consumers also set a lock (with the
##     potential post-process name of the file) for the next directory in the
##     chain. This is done to avoid files being processed by the next consumers
##     before the files are completely moved to the next directory.

## \fn sha STRING
## \brief Compute sha256sum of string
## \param STRING String to compute sum for
sha() {
  echo "${1##*/}" | sha256sum | cut -d' ' -f1
}

## \fn consumer_lock NAME [DIR]
## \brief Lock the given item thanks to its name
## \param NAME Name of the item to lock
## \param DIR Directory in which to create the lock (default to data)
consumer_lock() {
  mkdir "${2:-$set_lock_dir}/$(sha "$1")" 2>/dev/null
}

## \fn consumer_unlock NAME [DIR]
## \brief Unlock the given item thanks to its name
## \param NAME Name of the item to unlock
## \param DIR Directory in which to remove the lock (default to data)
consumer_unlock() {
  rm -rf "${2:-$set_lock_dir}/$(sha "$1")" 2>/dev/null
}

## \fn consumer_locked NAME [DIR]
## \brief Test if NAME is locked
## \param NAME Name of the item to test
## \param DIR Directory in which to check the lock (default to data)
consumer_locked() {
  [ -d "${2:-$get_lock_dir}/$(sha "$1")" ]
}

## \fn consumer_unlocked NAME [DIR]
## \brief Test if NAME is unlocked
## \param NAME Name of the item to test
## \param DIR Directory in which to check the lock (default to data)
consumer_unlocked() {
  ! consumer_locked "$@"
}

## \fn consumer_get FILE...
## \brief Lock then move each given file into consumed directory
## \param FILE Single or multiple files to move into consumed directory
consumer_get() {
  local get_to
  get_to="$(consumer_location)"
  local item
  for item in "$@"; do
    # FIXME: if lock fails?
    consumer_lock "${item}"
    mv "${item}" "${get_to}"
    consumer_unlock "${item}"
  done
}

## \fn consumer_send DAEMON FILE...
## \brief Lock then move each given file to consumed directory of DAEMON
## \param DAEMON The daemon to send the files to (into its consumed directory)
## \param FILE Single or multiple files to move into consumed directory
consumer_send() {
  # TODO: handle name variants
  local daemon="$1"
  local send_to
  local set_lock
  send_to="$(${daemon} location)"
  set_lock="$(get_data_dir "${daemon}")"
  shift
  local item
  for item in "$@"; do
    # FIXME: if lock fails?
    consumer_lock "${item}" "${set_lock}"
    mv "${item}" "${send_to}"
    consumer_unlock "${item}" "${set_lock}"
  done
}

## \fn consumer_location
## \brief Return the path to the consumed directory
consumer_location() {
  echo "${consumed_dir}"
}

## \fn consumer_empty [DIR]
## \brief Test if consumed directory is empty
## \param DIR Directory to check (default to consumed directory)
consumer_empty() {
  local dir="${1:-$consumed_dir}"
  # shellcheck disable=SC2164
  ( [ -d "${dir}" ] && cd "${dir}"; [ "$(echo .* ./*)" = ". .. ./*" ]; )
}

## \fn consumer_consume NAME
## \brief Consume (process) file identified by NAME. You must rewrite this function.
## \param NAME Name of the file/folder to process
consumer_consume() {
  echo "consumer: (dummy) processing $1"
  sleep 3
}

## \fn consumer [params] [command]
## \brief Main consumer function. Handle arguments, launch the loop.
consumer() {
  local command
  get_lock_dir=$(init_data)
  set_lock_dir="${get_lock_dir}"

  while [ $# -ne 0 ]; do
    case $1 in
      ## \param consume DIR
      ## Directory to consume
      consume) consumed_dir="$2"; shift ;;
      ## \param empty-wait SECONDS
      ## Time to wait (in seconds) when consumed directory is empty
      empty-wait) empty_wait="$2"; shift ;;
      ## \param locked-wait SECONDS
      ## Time to wait (in seconds) when item is locked
      locked-wait) locked_wait="$2"; shift ;;
      ## \param (command) get ITEM...
      ## Move specified items into consumed directory
      get) command=get; shift; break ;;
      ## \param (command) send ITEM... DIR
      ## Lock then send specified items from consumed directory to another consumer
      send) command=send; shift; break ;;
      ## \param (command) location
      ## Return the path of the consumed directory
      location) command=location; shift; break ;;
    esac
    shift
  done

  ## \env consumed_dir Path to directory to consume
  if [ ! -d "${consumed_dir}" ]; then
    echo "consumer: consumed dir ${consumed_dir} does not exist" >&2
    exit 1
  fi

  case $command in
    get) consumer_get "$@"; exit $? ;;
    send) consumer_send "$@"; exit $? ;;
    location) consumer_location; exit 0 ;;
  esac

  if [ -z "${empty_wait}" ]; then
    ## \env empty_wait
    ## Time to wait (in seconds) when consumed directory is empty.
    empty_wait=2
  fi

  if [ -z "${locked_wait}" ]; then
    ## \env locked_wait
    ## Time to wait (in seconds) when all items in consumed directory are locked.
    locked_wait=0.5
  fi

  local all_locked item
  while true; do
    if ! consumer_empty "${consumed_dir}"; then
      all_locked=true
      for item in "${consumed_dir}"/*; do
        if consumer_lock "${item}"; then
          all_locked=false
          consumer_consume "${item}"
          consumer_unlock "${item}"
        fi
      done
      ${all_locked} && sleep ${locked_wait}
    else
      sleep ${empty_wait}
    fi
  done
}
