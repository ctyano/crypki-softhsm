#!/usr/bin/env bash
[ "${DEBUG}" = "true" ] && set -x

if [ -z "${ROOT}" ]; then
    BINDIR=$(dirname "$0")
    export ROOT=$(cd $BINDIR;pwd)
    echo "Setting Crypki root directory to ${ROOT}"
fi

export CRYPKI_STOP_TIMEOUT=${CRYPKI_STOP_TIMEOUT:-30}
export CRYPKI_PID_DIR=${CRYPKI_PID_DIR:-$ROOT/pid}
export CRYPKI_LOG_DIR=${CRYPKI_LOG_DIR:-$ROOT/logs}
export CRYPKI_CONFIG_FILE=${CRYPKI_CONFIG_FILE:-$ROOT/crypki-softhsm.json}

# make sure our pid and log directories exist

mkdir -p "${CRYPKI_PID_DIR}"
mkdir -p "${CRYPKI_LOG_DIR}"

# initialize hsm

/bin/bash -x /opt/crypki/init_hsm.sh

/usr/bin/crypki-bin -config ${CRYPKI_CONFIG_FILE} 2>&1 &
PID=$!

sleep 2;
if ! kill -0 "${PID}" > /dev/null 2>&1; then
    exit 1
fi

force_shutdown() {
    echo 'Will forcefully stopping Crypki...'
    kill -9 ${PID} >/dev/null 2>&1
    echo 'Forcefully stopped Crypki success'
    exit 1
}
shutdown() {
    if [ -z ${PID} ]; then
        echo 'Crypki is not running'
        exit 1
    else
        if ! kill -0 ${PID} > /dev/null 2>&1; then
            echo 'Crypki is not running'
            exit 1
        else
            # start shutdown
            echo 'Will stopping Crypki...'
            kill ${PID}

            # wait for shutdown
            count=0
            while [ -d "/proc/${PID}" ]; do
                echo 'Shutdown is in progress... Please wait...'
                sleep 1
                count="$((count + 1))"
    
                if [ "${count}" = "${CRYPKI_STOP_TIMEOUT}" ]; then
                    break
                fi
            done
            if [ "${count}" != "${CRYPKI_STOP_TIMEOUT}" ]; then
                echo 'Shutdown completed.'
            fi

            # if not success, force shutdown
            if kill -0 ${PID} > /dev/null 2>&1; then
                force_shutdown
            fi
        fi
    fi

    # confirm Crypki stopped
    if ! kill -0 ${PID} > /dev/null 2>&1; then
        exit 0
    fi
}

# SIGINT
trap shutdown 2

# SIGTERM
trap shutdown 15

# stream logs
echo 'Initilizing Crypki logs...'
touch ${CRYPKI_LOG_DIR}/server.log
echo 'Start printing Crypki logs...'
tail -f ${CRYPKI_LOG_DIR}/server.log &

# wait
wait ${PID}

