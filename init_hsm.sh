#!/usr/bin/env bash
set -euo pipefail
umask 022

error() {
	echo "$@" >&2
	exit 1
}

SOPIN=1234
USERPIN=123456

modulepath="/usr/lib/softhsm/libsofthsm2.so" # softlink to the exact shared library based on the os arch
slot_pubkeys_path="/opt/crypki/slot_pubkeys"

user_ssh_label="user_ssh"
host_x509_label="host_x509"
host_ssh_label="host_ssh"
sign_blob_label="sign_blob"
user_ssh_keytype="EC:secp256r1"
host_x509_keytype="EC:secp256r1"
host_ssh_keytype="rsa:4096"
sign_blob_keytype="rsa:4096"
user_ssh_cipher_cmd="ec"
host_x509_cipher_cmd="ec"
host_ssh_cipher_cmd="rsa"
sign_blob_cipher_cmd="rsa"

#
# check for required binaries and libraries
#
if [ "`uname -s`" != "Linux" ]; then
	error "This only works on linux because required binaries and libraries are only available and tested on linux."
fi
p11tool="`which pkcs11-tool 2>/dev/null`"
p11tool="${p11tool:=/usr/bin/pkcs11-tool}"
if [ ! -x "${p11tool}" ]; then
	error "Can't find pkcs11-tool binary in path or /usr/bin/pkcs11-tool. Needed to configure the HSM/PKCS#11 device.
	yum -y install opensc or apt-get install opensc # (or local equivalent package)"
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

set -e # exit if anything at all fails after here

#
# {re-}initialize slots with SO PIN
#
export user_ssh_slot=`${softhsm} --init-token --slot 0 --label ${user_ssh_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`
export host_x509_slot=`${softhsm} --init-token --slot 1 --label ${host_x509_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`
export host_ssh_slot=`${softhsm} --init-token --slot 2 --label ${host_ssh_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`
export sign_blob_slot=`${softhsm} --init-token --slot 3 --label ${sign_blob_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`

# Generate the Keys in the PKCS11 slot, or Import the Keys to the PKCS11 slot
if [ -z "${USER_SSH_PRIVATE_KEY:=}" -o -z "${USER_SSH_PUBLIC_KEY:=}" ]; then
    echo "Generating keypair to slot:${user_ssh_slot} label:${user_ssh_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${user_ssh_slot} --keypairgen --label ${user_ssh_label} --key-type ${user_ssh_keytype} --private
else
    echo "Importing file:${USER_SSH_PRIVATE_KEY} to slot:${user_ssh_slot} label:${user_ssh_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${user_ssh_slot} --write-object ${USER_SSH_PRIVATE_KEY} --label ${user_ssh_label} --type privkey
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${user_ssh_slot} --write-object ${USER_SSH_PUBLIC_KEY} --label ${user_ssh_label} --type pubkey
fi
if [ -z "${HOST_X509_PRIVATE_KEY:=}" -o -z "${HOST_X509_PUBLIC_KEY:=}" ]; then
    echo "Generating keypair to slot:${host_x509_slot} label:${host_x509_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_x509_slot} --keypairgen --label ${host_x509_label} --key-type ${host_x509_keytype} --private
else
    echo "Importing file:${HOST_X509_PRIVATE_KEY} to slot:${host_x509_slot} label:${host_x509_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_x509_slot} --write-object ${HOST_X509_PRIVATE_KEY} --label ${host_x509_label} --type privkey
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_x509_slot} --write-object ${HOST_X509_PUBLIC_KEY} --label ${host_x509_label} --type pubkey
fi
if [ -z "${HOST_SSH_PRIVATE_KEY:=}" -o -z "${HOST_SSH_PUBLIC_KEY:=}" ]; then
    echo "Generating keypair to slot:${host_ssh_slot} label:${host_ssh_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_ssh_slot} --keypairgen --label ${host_ssh_label} --key-type ${host_ssh_keytype} --private
else
    echo "Importing file:${HOST_SSH_PRIVATE_KEY} to slot:${host_ssh_slot} label:${host_ssh_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_ssh_slot} --write-object ${HOST_SSH_PRIVATE_KEY} --label ${host_ssh_label} --type privkey
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_ssh_slot} --write-object ${HOST_SSH_PUBLIC_KEY} --label ${host_ssh_label} --type pubkey
fi
if [ -z "${SIGN_BLOB_PRIVATE_KEY:=}" -o -z "${SIGN_BLOB_PUBLIC_KEY:=}" ]; then
    echo "Generating keypair to slot:${sign_blob_slot} label:${sign_blob_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${sign_blob_slot} --keypairgen --label ${sign_blob_label} --key-type ${sign_blob_keytype} --private
else
    echo "Importing file:${SIGN_BLOB_PRIVATE_KEY} to slot:${sign_blob_slot} label:${sign_blob_label}"
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${sign_blob_slot} --write-object ${SIGN_BLOB_PRIVATE_KEY} --label ${sign_blob_label} --type privkey
    ${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${sign_blob_slot} --write-object ${SIGN_BLOB_PUBLIC_KEY} --label ${sign_blob_label} --type pubkey
fi

# Store the CA public keys of each PKCS11 slot.
# The public keys are useful to configure CA for PSSHCA deployment.
if [ -z "${USER_SSH_PRIVATE_KEY:=}" -o -z "${USER_SSH_PUBLIC_KEY:=}" ]; then
${p11tool} --module ${modulepath} -r --type pubkey --slot ${user_ssh_slot} --label ${user_ssh_label} -l --output-file ${slot_pubkeys_path}/${user_ssh_label}_pub.der --pin=${USERPIN}
${openssl} ${user_ssh_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${user_ssh_label}_pub.der -pubin -out ${slot_pubkeys_path}/${user_ssh_label}_pub.pem
fi
if [ -z "${HOST_X509_PRIVATE_KEY:=}" -o -z "${HOST_X509_PUBLIC_KEY:=}" ]; then
${p11tool} --module ${modulepath} -r --type pubkey --slot ${host_x509_slot} --label ${host_x509_label} -l --output-file ${slot_pubkeys_path}/${host_x509_label}_pub.der --pin=${USERPIN}
${openssl} ${host_x509_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${host_x509_label}_pub.der -pubin -out ${slot_pubkeys_path}/${host_x509_label}_pub.pem
fi
if [ -z "${HOST_SSH_PRIVATE_KEY:=}" -o -z "${HOST_SSH_PUBLIC_KEY:=}" ]; then
${p11tool} --module ${modulepath} -r --type pubkey --slot ${host_ssh_slot} --label ${host_ssh_label} -l --output-file ${slot_pubkeys_path}/${host_ssh_label}_pub.der --pin=${USERPIN}
${openssl} ${host_ssh_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${host_ssh_label}_pub.der -pubin -out ${slot_pubkeys_path}/${host_ssh_label}_pub.pem
fi
if [ -z "${SIGN_BLOB_PRIVATE_KEY:=}" -o -z "${SIGN_BLOB_PUBLIC_KEY:=}" ]; then
${p11tool} --module ${modulepath} -r --type pubkey --slot ${sign_blob_slot} --label ${sign_blob_label} -l --output-file ${slot_pubkeys_path}/${sign_blob_label}_pub.der --pin=${USERPIN}
${openssl} ${sign_blob_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${sign_blob_label}_pub.der -pubin -out ${slot_pubkeys_path}/${sign_blob_label}_pub.pem
fi

CRYPKI_CONFIG=`sed -e "s/SLOTNUM_USER_SSH/${user_ssh_slot}/g; s/SLOTNUM_HOST_X509/${host_x509_slot}/g; s/SLOTNUM_HOST_SSH/${host_ssh_slot}/g; s/SLOTNUM_SIGN_BLOB/${sign_blob_slot}/g" ${CRYPKI_CONFIG_TEMPLATE:-/opt/crypki/crypki.conf.sample}`

echo "${CRYPKI_CONFIG}" > ${CRYPKI_CONFIG_FILE:-/opt/crypki/crypki-softhsm.json}
