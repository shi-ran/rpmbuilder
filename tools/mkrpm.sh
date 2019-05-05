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

function get_prod_env {
    echo "== Get the release version"
    if [ -z "${PRODUCT}" ] || [ -z "${BRANCH}" ] || [ -z "${BUILDTAG}" ]; then
        err "ERROR: PRODUCT, BRANCH and BUILDTAG need to be defined"
    fi
    destdir="${curdir}/${PRODUCT}/${BRANCH}/${BUILDTAG}"
    release=$(echo ${BUILDTAG} | awk -F- '{print $2}')
}

function create_source_archive {
    echo "==create the source archive ${tarfile}"
    tar -zcvf ${tarfile} $(grep -v ^# ${instfile} | sed -e "s/\${version}/${version}/g")
    if [ $? != 0 ]; then
        err "ERROR: failed to create ${tarfile}"
    fi
    mkdir -p ${tmppath}/${name}-${version}
    (cd ${tmppath}/${name}-${version}; tar zxvf ${tarfile})
    (cd ${tmpfile}; tar zxvf ${tarfile} .)
    rm -rf ${tmppath}/${name}-${version}
}

function create_rpm_env{
    echo "==Create the rpm environment under ${rpmdir}"
    mkdir -p ${rpmdir}/{RPMS,SRPMS,BUILD,SOURCE,SPECS,tmp}
    specfile_dest="${topdir}/SPEC/$(basename ${specfile})"
    cat ${specfile} | sed -r -e "s/^Release\s*.*$/Release: ${release}/" >${specfile_dest}
    if [ $? -ne 0 ]; then
        err "ERROR: copy ${sepcfile} to ${specfile_dest} failed"
    fi
}

function build_rpm{
    echo "== Build the ${name} rpm"
    pushd ${rpmdir}
    rm -f ${rpmmacros}
    echo "for debug purpose cat content of ${rpmmacros}:"
    [ -e ${rpmmacros} ] && cat ${rpmmacros}
    ${rpmbuild} --define "_topdir ${topdir}"\
                --define "_builddir ${builddir}"\
                --define "_tmppath ${tmppath}" -bb ${specfile}
    if [ $? != 0 ]; then
        err "ERROR: rpm build failed to create rpm"
    fi
    echo "For debug purpose cat content of ${rpmmacros}"
    [ -e ${rpmmacros} ] && cat ${rpmmacros}
    popd
}

function move_rpm{
    echo "==Move ${rpmfile} to ${destdir}"
    mkdir -p ${destdir}
    cp -pr ${rpmfile} ${destdir}
    if [ $? != 0 ]; then
        err "ERROR: move ${rpmfile} failed"
    fi
}

function gen_coverage_spec{
    _sepcfile_dir="$(dirname ${specfile})"
    _instfile_dir="$(dirname ${instfile})"
    _project_name=$(basename ${specfile} .spec)
    _cov_suffix="_code_coverage"
    _cov_db_list="${_sepcfile_dir}/${_project_name}${_cov_suffix}_db.list"

    _orig_specfile=${specfile}
    _orig_instfile=${instfile}
    specfile="${_specfile_dir}/${_project_name}${_cov_suffix}.spec"
    instfile="${_instfile_dir}/${_project_name}${_cov_suffix}.inst"

    readarray clover_dbs < ${_cov_db_list}
    inst_cmds=()
    for db in ${clover_dbs[@]}; do
        inst_cmds+="install -D -m 0600 ${db} %{buildroot}${coverage_dir}/$(basename ${db})\n"
    done
    echo "Generating coverage ${specfile} ..."
    sed -e "/%install/ {
# skip the first line
    n
# append db files
    a ${inst_cmds[@]}
}" -e "/%files/ {
# skip the first line
    n
# append db files
    a %attr(400,-,-) ${coverage_dir}/*
}" ${_orig_specfile} > ${specfile}

    echo "Generating coverage ${instfile} ..."
    cat ${_orig_instfile} <(printf '%s\n' ${clover_dbs[@]}) > ${instfile}
}

while getopts "c" opt; do
    case ${opt} in
      c) mode="coverage"
        ;;
    \?)
      err "${usage}"
        ;;
    esac
done
shift $((OPINTD-1))

if [ $# -ne 1 ]; then
    err "${usage}"
fi

sepcfile=$1
instfile="$(dirname ${specfile})/$(basename ${specfile} .spec).inst"

if [ "${instfile:0:1}" != "/" ]; then
    instfile="${curdir}/${instfile}"
fi

if [ ! -e ${specfile} ]; then
    err "ERROR: ${specfile} spec file not found"
fi

if [ ! -e ${instfile} ]; then
    err "ERROR: ${instfile} inst file not found"
fi

if [ x"${mode}" == x"coverage" ]; then
    gen_coverage_spec
fi

name=$(cat ${specfile}) | grep -E "^Name\s*:" | sed -r -e "s/^Name\s*:\s*(.*)\s*$/\1/"
version=$(cat ${specfile}) | grep -E "^Version\s*:" | sed -r -e "s/^Version\s*:\s*(.*)\s*$/\1/"
builder=$(cat ${specfile}) | grep -E "^BuildArch\s*:" | sed -r -e "s/^BuildArch\s*:\s*(.*)\s*$/\1/"
release=$(cat ${specfile}) | grep -E "^Release\s*:" | sed -r -e "s/^Release\s*:\s*(.*)\s*$/\1/"

[ -n "${JENKINS_URL}" ] && get_prod_env

tarfile="${rpmdir}/SOURCES/${name}-${version}.tar.gz"
rpmfile="${rpmdir}/RPMS/${buildarch}/${name}-${version}-${release}.${buildarch}.rpm"

create_rpm_env
create_source_archive
build_rpm
[ -n "${JENKINS_URL}" ] && move_rpm


echo Done