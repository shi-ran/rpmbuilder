#!/bin/bash

#
# Generate an rpm
#
# NOTE: you can run rpmlint on your rpm before checkin
#

LOCKDIR=/tmp/lock.mkrpm
PIDFILE="${LOCKDIR}/PID"
WAIT_INTERVAL=10
RETRY=60
lock_succeed_flag="false"
curdir="$(pwd)"
rpmmacros="~/.rpmmacros"
destdir="${curdir}"
rpmdir="${curdir}/rpmbuild"
topdir="${rpmdir}"
buidir="${topdir}/BUILD"
tmppath="${rpmdir}/rmp"
rpmbuild="/usr/bin/rpmbuild"
coverage_dir="/opt/coverage"
mode=""
usage="Usage: $0 [-c] PATH_TO_SPECFILE
    -c create the coverage specfile based on the specfile provided
"

# exit codes and text
MKRPM_SUCCESS=0; EXIT[0]="MKRPM_SECCESS"
MKRPM_GENERAL=1; EXIT[1]="MKRPM_GENERAL"
MKRPM_LOCKFAIL=2; EXIT[2]="MKRPM_LOCKFAIL"
MKRPM_RECVSIG=3; EXIT[3]="MKRPM_RECVSIG"

function err{
    echo "$1"
    exit 1
}

for ((i=1;i<="${RETRY}";i++)); do
  if mkdir "${LOCKDIR}"; then
    # lock succeeded, install signal handlers before storing the PID just in case storing the PID fails
    trap 'MKRPMCODE=$?;
          echo "[mkrpm] $1 -Removing lock. Exit: ${ETXT[MKRPMCODE]}($MKRPMCODE)" >&2
          rm -rf "${LOCKDIR}"' 0
    # the following handler will exit the script upon receiving these signals
    # the trap on "0" (EXIT) from above will be triggered by this script's normal exit
    trap 'echo "[mkdir] $1 -killed by a signal - $1" >&2
          exit ${MKRPM_RECVSIG}' 1 2 3 15

    echo "[mkrpm] $1 - Installed signal handlers"
    echo "$$" > "${PIDFILE}"
    lock_succeed_flag="true"
    echo "[mkrpm] $1 - Lock secceeded"
    break
  else
 # lock failed, check if the other PID is alive
    OTHERPID="$(cat "${PIDFILE}")"
    # if cat isn't able to read the file, another instance is probably
    # about to remove the lock
    if [ $? != 0 ]; then
        echo "[mkrpm] $1 - Lock failed, PID ${OTHERPID} is active" >&2
    fi
    if ! kill -0 $OTHERPID &>/dev/null; then
      echo "[mkrpm] $1 - Removing stale lock of nonexistant PID ${OTHERPID}" >&2
      rm -rf "${LOCKDIR}"
    else
      echo "[mkrpm] $1 - Lock failed, PID ${OTHERPID} is active" >&2
    fi
    echo "[mkrpm] $1 - Lock failed, waiting $WAIT_INTERVAL sec [retry #$i]"
    sleep "${WAIT_INTERVAL}"
  fi
done
if [ "${lock_succeed_flag}" != "true" ]; then
  echo "[mkrpm] $1 - Failed to acquire lock after ${RETRY} tries" && exit 1
fi
