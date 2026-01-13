#!/usr/bin/env bash
set -euo pipefail
umask 022

error() {
	echo "$@" >&2
	exit 1
}

SOPIN=1234
USERPIN=123456

CACERT_CRYPKI_CONFIG_TEMPLATE=${CACERT_CRYPKI_CONFIG_TEMPLATE:-/opt/crypki/cacert.crypki.config.template}
CACERT_CRYPKI_CONFIG_FILE=${CACERT_CRYPKI_CONFIG_FILE:-/opt/crypki/cacert.crypki-softhsm.json}
CACERT_FILE=${CACERT_FILE:-/tmp/ca.cert.pem}
SERVERCERT_VALIDITY_DAYS=${SERVERCERT_VALIDITY_DAYS:-730}
SERVERCERT_CSR_CONFIG_FILE=${SERVERCERT_CSR_CONFIG_FILE:-/opt/crypki/crypki.openssl.config}
SERVERCERT_CSR_FILE=${SERVERCERT_CSR_FILE:-/tmp/servercert.csr.pem}
SERVERCERT_KEY_FILE=${SERVERCERT_KEY_FILE:-/tmp/server.key.pem}
SERVERCERT_FILE=${SERVERCERT_FILE:-/tmp/server.cert.pem}

modulepath="/usr/lib/softhsm/libsofthsm2.so" # softlink to the exact shared library based on the os arch
slot_pubkeys_path="/opt/crypki/slot_pubkeys"

host_x509_label="host_x509"
host_x509_keytype="EC:secp256r1"
host_x509_cipher_cmd="ec"

#
# check for required binaries and libraries
#
if [ "`uname -s`" != "Linux" ]; then
	error "This only works on linux because required binaries and libraries are only available and tested on linux."
fi
softhsm="`which softhsm2-util 2>/dev/null`"
softhsm="${softhsm:=/usr/bin/softhsm2-util}"
if [ ! -x "${softhsm}" ]; then
	error "Can't find softhsm binary in path or /usr/bin/softhsm2-util. Needed to configure the HSM/PKCS#11 device.
	yum -y install softhsm or apt-get install softhsm # (or local equivalent package)"
fi
openssl="${openssl:=/usr/bin/openssl}"
if [ ! -x "${openssl}" ]; then
	error "Can't find openssl binary in path or /usr/bin/openssl. Needed to install openssl.
	yum -y install openssl or apt-get install openssl # (or local equivalent package)"
fi
gencacert="${gencacert:=/usr/bin/gen-cacert}"
if [ ! -x "${gencacert}" ]; then
	error "Can't find gen-cacert binary in path or /usr/bin/gen-cacert. The container image may be corrupted."
fi
signx509cert="${signx509cert:=/usr/bin/sign-x509cert}"
if [ ! -x "${signx509cert}" ]; then
	error "Can't find sign-x509cert binary in path or /usr/bin/sign-x509cert. The container image may be corrupted."
fi

set -e # exit if anything at all fails after here
#
# {re-}initialize slots with SO PIN
#
export host_x509_slot=`${softhsm} --init-token --slot 1 --label ${host_x509_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`

CACERT_CRYPKI_CONFIG=`sed -e "s/SLOTNUM_HOST_X509/${host_x509_slot}/g" ${CACERT_CRYPKI_CONFIG_TEMPLATE}`

echo "${CACERT_CRYPKI_CONFIG}" > ${CACERT_CRYPKI_CONFIG_FILE}

${gencacert} -config=${CACERT_CRYPKI_CONFIG_FILE} -out=${CACERT_FILE} -skip-hostname -skip-ips

${openssl} ecparam -name prime256v1 -genkey -noout -out ${SERVERCERT_KEY_FILE}
${openssl} req -config ${SERVERCERT_CSR_CONFIG_FILE} -new -key ${SERVERCERT_KEY_FILE} -out ${SERVERCERT_CSR_FILE} -extensions ext_req
${signx509cert} -config=${CACERT_CRYPKI_CONFIG_FILE} -days=${SERVERCERT_VALIDITY_DAYS} -cacert=${CACERT_FILE} -in=${SERVERCERT_CSR_FILE} -out=${SERVERCERT_FILE}

${openssl} verify -CAfile ${CACERT_FILE} ${SERVERCERT_FILE}

