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
CACERT_K8S_SECRET=${CACERT_K8S_SECRET:-crypki-ca}
SERVERCERT_VALIDITY_DAYS=${SERVERCERT_VALIDITY_DAYS:-730}
SERVERCERT_CSR_CONFIG_FILE=${SERVERCERT_CSR_CONFIG_FILE:-/opt/crypki/crypki.openssl.config}
SERVERCERT_CSR_FILE=${SERVERCERT_CSR_FILE:-/tmp/servercert.csr.pem}
SERVERCERT_KEY_FILE=${SERVERCERT_KEY_FILE:-/tmp/server.key.pem}
SERVERCERT_FILE=${SERVERCERT_FILE:-/tmp/server.cert.pem}
CLIENTCERT_VALIDITY_DAYS=${CLIENTCERT_VALIDITY_DAYS:-1}
CLIENTCERT_CSR_CONFIG_FILE=${CLIENTCERT_CSR_CONFIG_FILE:-/opt/crypki/crypki.openssl.config}
CLIENTCERT_CSR_FILE=${CLIENTCERT_CSR_FILE:-/tmp/clientcert.csr.pem}
CLIENTCERT_KEY_FILE=${CLIENTCERT_KEY_FILE:-/tmp/client.key.pem}
CLIENTCERT_FILE=${CLIENTCERT_FILE:-/tmp/client.cert.pem}
CLIENTCERT_K8S_SECRET=${CLIENTCERT_K8S_SECRET:-crypki-client}
EXPORT_CACERT_TO_K8S_SECRET=${EXPORT_CACERT_TO_K8S_SECRET:-true}

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
export user_ssh_slot=`${softhsm} --init-token --slot 0 --label ${user_ssh_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`
export host_x509_slot=`${softhsm} --init-token --slot 1 --label ${host_x509_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`
export host_ssh_slot=`${softhsm} --init-token --slot 2 --label ${host_ssh_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`
export sign_blob_slot=`${softhsm} --init-token --slot 3 --label ${sign_blob_label} --so-pin ${SOPIN} --pin ${USERPIN} | awk '{print $NF}'`

# Generate the Keys in the PKCS11 slot
echo "Generating keypair to slot:${user_ssh_slot} label:${user_ssh_label}"
${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${user_ssh_slot} --keypairgen --label ${user_ssh_label} --key-type ${user_ssh_keytype} --private
echo "Generating keypair to slot:${host_x509_slot} label:${host_x509_label}"
${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_x509_slot} --keypairgen --label ${host_x509_label} --key-type ${host_x509_keytype} --private
echo "Generating keypair to slot:${host_ssh_slot} label:${host_ssh_label}"
${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${host_ssh_slot} --keypairgen --label ${host_ssh_label} --key-type ${host_ssh_keytype} --private
echo "Generating keypair to slot:${sign_blob_slot} label:${sign_blob_label}"
${p11tool} --module ${modulepath} --pin ${USERPIN} --slot ${sign_blob_slot} --keypairgen --label ${sign_blob_label} --key-type ${sign_blob_keytype} --private

# Store the CA public keys of each PKCS11 slot.
# The public keys are useful to configure CA for PSSHCA deployment.
${p11tool} --module ${modulepath} -r --type pubkey --slot ${user_ssh_slot} --label ${user_ssh_label} -l --output-file ${slot_pubkeys_path}/${user_ssh_label}_pub.der --pin=${USERPIN}
${openssl} ${user_ssh_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${user_ssh_label}_pub.der -pubin -out ${slot_pubkeys_path}/${user_ssh_label}_pub.pem
${p11tool} --module ${modulepath} -r --type pubkey --slot ${host_x509_slot} --label ${host_x509_label} -l --output-file ${slot_pubkeys_path}/${host_x509_label}_pub.der --pin=${USERPIN}
${openssl} ${host_x509_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${host_x509_label}_pub.der -pubin -out ${slot_pubkeys_path}/${host_x509_label}_pub.pem
${p11tool} --module ${modulepath} -r --type pubkey --slot ${host_ssh_slot} --label ${host_ssh_label} -l --output-file ${slot_pubkeys_path}/${host_ssh_label}_pub.der --pin=${USERPIN}
${openssl} ${host_ssh_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${host_ssh_label}_pub.der -pubin -out ${slot_pubkeys_path}/${host_ssh_label}_pub.pem
${p11tool} --module ${modulepath} -r --type pubkey --slot ${sign_blob_slot} --label ${sign_blob_label} -l --output-file ${slot_pubkeys_path}/${sign_blob_label}_pub.der --pin=${USERPIN}
${openssl} ${sign_blob_cipher_cmd} -inform DER -in ${slot_pubkeys_path}/${sign_blob_label}_pub.der -pubin -out ${slot_pubkeys_path}/${sign_blob_label}_pub.pem

CRYPKI_CONFIG=`sed -e "s/SLOTNUM_USER_SSH/${user_ssh_slot}/g; s/SLOTNUM_HOST_X509/${host_x509_slot}/g; s/SLOTNUM_HOST_SSH/${host_ssh_slot}/g; s/SLOTNUM_SIGN_BLOB/${sign_blob_slot}/g" ${CRYPKI_CONFIG_TEMPLATE:-/opt/crypki/crypki.conf.sample}`

echo "${CRYPKI_CONFIG}" > ${CRYPKI_CONFIG_FILE:-/opt/crypki/crypki-softhsm.json}

CACERT_CRYPKI_CONFIG=`sed -e "s/SLOTNUM_HOST_X509/${host_x509_slot}/g" ${CACERT_CRYPKI_CONFIG_TEMPLATE}`

echo "${CACERT_CRYPKI_CONFIG}" > ${CACERT_CRYPKI_CONFIG_FILE}

${gencacert} -config=${CACERT_CRYPKI_CONFIG_FILE} -out=${CACERT_FILE} -skip-hostname -skip-ips

${openssl} ecparam -name prime256v1 -genkey -noout -out ${SERVERCERT_KEY_FILE}
${openssl} req -config ${SERVERCERT_CSR_CONFIG_FILE} -new -key ${SERVERCERT_KEY_FILE} -out ${SERVERCERT_CSR_FILE} -extensions ext_req
${signx509cert} -config=${CACERT_CRYPKI_CONFIG_FILE} -days=${SERVERCERT_VALIDITY_DAYS} -cacert=${CACERT_FILE} -in=${SERVERCERT_CSR_FILE} -out=${SERVERCERT_FILE}

${openssl} verify -CAfile ${CACERT_FILE} ${SERVERCERT_FILE}

${openssl} ecparam -name prime256v1 -genkey -noout -out ${CLIENTCERT_KEY_FILE}
${openssl} req -config ${CLIENTCERT_CSR_CONFIG_FILE} -new -key ${CLIENTCERT_KEY_FILE} -out ${CLIENTCERT_CSR_FILE} -extensions ext_req
${signx509cert} -config=${CACERT_CRYPKI_CONFIG_FILE} -days=${CLIENTCERT_VALIDITY_DAYS} -cacert=${CACERT_FILE} -in=${CLIENTCERT_CSR_FILE} -out=${CLIENTCERT_FILE}

${openssl} verify -CAfile ${CACERT_FILE} ${CLIENTCERT_FILE}

# --- NEW: Export CA and administration client certificates to Kubernetes Secret ---

export_ca_to_k8s_secret() {
    local ca_secret_name="${1:-${CACERT_K8S_SECRET}}"
    local ca_file="${2}"
    local namespace

    # Auto-detect namespace or default to 'default'
    if [ -f /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
        namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    else
        namespace="default"
    fi

    echo "==> Attempting to export CA Cert to K8s Secret: ${ca_secret_name} in namespace: ${namespace}"

    # Check if necessary K8s token exists
    local token_path="/var/run/secrets/kubernetes.io/serviceaccount/token"
    local ca_cert_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"

    if [ ! -f "$token_path" ]; then
        echo "    Error: K8s ServiceAccount token not found. Not running in K8s?"
        return 1
    fi

    # Prepare JSON payload
    # We must base64 encode the cert content single-line
    local b64_cacert
    b64_cacert=$(cat "$ca_file" | base64 | tr -d '\n')

    local ca_json_payload
    ca_json_payload=$(cat <<EOF
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "${ca_secret_name}",
    "namespace": "${namespace}"
  },
  "type": "Opaque",
  "data": {
    "ca.crt": "${b64_cacert}"
  }
}
EOF
)

    # Send Request to K8s API
    # We use --fail to detect errors (like 403 Forbidden)
    local k8s_api="https://kubernetes.default.svc"

    # 1. Try to create (POST)
    echo "    Creating secret..."
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --cacert "$ca_cert_path" \
        -H "Authorization: Bearer $(cat $token_path)" \
        -H "Content-Type: application/json" \
        -X POST "${k8s_api}/api/v1/namespaces/${namespace}/secrets" \
        -d "$ca_json_payload")

    if [ "$http_code" -eq 201 ]; then
        echo "    Secret created successfully."
    elif [ "$http_code" -eq 409 ]; then
        echo "    Secret already exists. Attempting update (PUT)..."
        # 2. If exists, update (PUT)
        curl -s --cacert "$ca_cert_path" \
            -H "Authorization: Bearer $(cat $token_path)" \
            -H "Content-Type: application/json" \
            -X PUT "${k8s_api}/api/v1/namespaces/${namespace}/secrets/${ca_secret_name}" \
            -d "$ca_json_payload"
        echo "    Secret updated."
    else
        echo "    Failed to create secret. HTTP Code: $http_code"
        echo "    Ensure the Pod's ServiceAccount has \"create\" and \"update\" permissions on Secrets."
    fi
}

export_clientcert_to_k8s_secret() {
    local client_secret_name="${1:-${CLIENTCERT_K8S_SECRET}}"
    local clientcert_file="${2}"
    local clientkey_file="${3}"
    local namespace

    # Auto-detect namespace or default to 'default'
    if [ -f /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
        namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
    else
        namespace="default"
    fi

    echo "==> Attempting to export Client Cert to K8s Secret: ${client_secret_name} in namespace: ${namespace}"

    # Check if necessary K8s token exists
    local token_path="/var/run/secrets/kubernetes.io/serviceaccount/token"
    local ca_cert_path="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
    local client_cert_path="/var/run/secrets/kubernetes.io/serviceaccount/tls.crt"
    local client_key_path="/var/run/secrets/kubernetes.io/serviceaccount/tls.key"

    if [ ! -f "$token_path" ]; then
        echo "    Error: K8s ServiceAccount token not found. Not running in K8s?"
        return 1
    fi

    # Prepare JSON payload
    # We must base64 encode the cert content single-line
    local b64_clientcert
    b64_clientcert=$(cat "$clientcert_file" | base64 | tr -d '\n')
    local b64_clientkey
    b64_clientkey=$(cat "$clientkey_file" | base64 | tr -d '\n')

    local client_json_payload
    client_json_payload=$(cat <<EOF
{
  "apiVersion": "v1",
  "kind": "Secret",
  "metadata": {
    "name": "${client_secret_name}",
    "namespace": "${namespace}"
  },
  "type": "Opaque",
  "data": {
    "tls.key": "${b64_clientkey}",
    "tls.crt": "${b64_clientcert}"
  }
}
EOF
)

    # Send Request to K8s API
    # We use --fail to detect errors (like 403 Forbidden)
    local k8s_api="https://kubernetes.default.svc"

    # 1. Try to create (POST)
    echo "    Creating secret..."
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --cacert "$ca_cert_path" \
        -H "Authorization: Bearer $(cat $token_path)" \
        -H "Content-Type: application/json" \
        -X POST "${k8s_api}/api/v1/namespaces/${namespace}/secrets" \
        -d "$client_json_payload")

    if [ "$http_code" -eq 201 ]; then
        echo "    Secret created successfully."
    elif [ "$http_code" -eq 409 ]; then
        echo "    Secret already exists. Attempting update (PUT)..."
        # 2. If exists, update (PUT)
        curl -s --cacert "$ca_cert_path" \
            -H "Authorization: Bearer $(cat $token_path)" \
            -H "Content-Type: application/json" \
            -X PUT "${k8s_api}/api/v1/namespaces/${namespace}/secrets/${client_secret_name}" \
            -d "$client_json_payload"
        echo "    Secret updated."
    else
        echo "    Failed to create secret. HTTP Code: $http_code"
        echo "    Ensure the Pod's ServiceAccount has \"create\" and \"update\" permissions on Secrets."
    fi
}

# Trigger export if flag is set
if [ "${EXPORT_CACERT_TO_K8S_SECRET}" = "true" ]; then
    set -x
    export_ca_to_k8s_secret "${CACERT_K8S_SECRET}" "${CACERT_FILE}"
    export_clientcert_to_k8s_secret "${CLIENTCERT_K8S_SECRET}" "${CLIENTCERT_FILE}" "${CLIENTCERT_KEY_FILE}"
fi
