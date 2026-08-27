#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# License found in the LICENSE file in the root directory
# of this source tree.

set -Eeuo pipefail

working_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

haproxy_cfg_default="${working_dir}/whatsapp-haproxy.cfg"

function echo_err() {
	echo -e "\033[0;31m${1:-}\033[0m" >&2
}

function exit_with_err() {
    local exit_code="${2:-}"

    if [ -z "$exit_code" ]; then
        exit_code="1"
    fi

    if [ "$exit_code" -eq 0 ]; then
        exit_code="1"
    fi

    echo_err "${1:-Error}"
    exit "$exit_code"
}

function usage() {
    local exit_code="${1-}"
    if [ -z "$exit_code" ]; then
      exit_code="0"
    fi
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -c|--config PATH - Path to config file with envs params"
    echo "                     Also can be passed via env WHATSAPP_START_CONFIG_FILE"
    echo "                     Optional. Next envs can be export directly without using config file."
    echo "                     Config file should be dot env file with next variables:"
    echo "                     Start script envs:"
    echo "                     - WHATSAPP_HAPROXY_BIN - path to haproxy binary."
    echo "                         Optional, default: haproxy"
    echo "                     - WHATSAPP_PROXY_CONFIG_FILE - path to haproxy config."
    echo "                         Optional, default: $haproxy_cfg_default"
    echo "                     - WHATSAPP_PROXY_CERT_FILE - path to proxy tls key and cert."
    echo "                         Optional, default: /etc/haproxy/ssl/proxy.whatsapp.net.pem"
    echo "                         If file exists and not empty generating cert will skip."
    echo "                     - WHATSAPP_PROXY_CERT_FILE_CHOWN - if passed will chown to cert file to passed string"
    echo "                         Optional."
    echo "                     - WHATSAPP_PROXY_SSL_DNS - comma-separated dns names for add to certificate alt names."
    echo "                         Optional."
    echo "                     - WHATSAPP_PROXY_SSL_IP - comma-separated ip's for add to certificate alt ip's."
    echo "                         Optional."
    echo "                     "
    echo "                     Next variables will use for configure proxy in proxy config file:"
    echo "                     - WHATSAPP_STATS_BIND_PORT - port for bind haproxy prometheus metrics server."
    echo "                         If passed bind to 127.0.0.1:\${WHATSAPP_STATS_BIND_PORT}"
    echo "                         Optional."
    echo "                     - WHATSAPP_V4_HTTP_FRONTEND_BIND - http frontend bind string."
    echo "                         Optional, default: 127.0.0.1:80"
    echo "                     - WHATSAPP_V4_HTTP_FRONTEND_ACCEPT_PROXY_BIND - if passed, bind frontend with pass real ip for http."
    echo "                         Optional."
    echo "                     - WHATSAPP_V4_HTTPS_FRONTEND_BIND - https (media) frontend bind string"
    echo "                         Optional, default: 127.0.0.1:443"
    echo "                     - WHATSAPP_V4_HTTPS_FRONTEND_ACCEPT_PROXY_BIND - if passed bind frontend with pass real ip for https"
    echo "                         Optional."
    echo "                     - WHATSAPP_V4_XMPP_FRONTEND_BIND - xmpp frontend bind string"
    echo "                         Optional, default: 127.0.0.1:5222"
    echo "                     - WHATSAPP_V4_XMPP_FRONTEND_ACCEPT_PROXY_BIND - if passed bind frontend with pass real ip for xmpp"
    echo "                         Optional."
    echo "                     - WHATSAPP_V4_NET_FRONTEND_BIND - whatsapp net (chat) frontend bind string"
    echo "                         Optional, default: 127.0.0.1:7777"
    echo "                     - WHATSAPP_NET_DESTINATION - proxy destination for whatsapp net (chat) with tls"
    echo "                         Optional, default: whatsapp.net:443"
    echo "                     - WHATSAPP_XMPP_DESTINATION - proxy destination for xmpp"
    echo "                         Optional, default: g.whatsapp.net:5222"
    echo "                     - WHATSAPP_NET_HTTP_DESTINATION - proxy destination for whatsapp net (chat) without tls"
    echo "                         Optional, default: g.whatsapp.net:80"
    echo "                     "
    echo "  -h|--help          - Display this help message"
    exit "$exit_code"
}

if [ -z "${WHATSAPP_START_CONFIG_FILE:-}" ]; then
    WHATSAPP_START_CONFIG_FILE=""
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        -c|--config)
        if [[ -z "${2:-}" || "${2:-}" == -* ]]; then
            exit_with_err "Error: Argument for $1 is missing" >&2
        fi
        WHATSAPP_START_CONFIG_FILE="${2-}"
        shift 2
        ;;
        -h|--help)
        usage "0"
        ;;
        *)
        echo_err "Unknown argument '${1}'"
        usage "1"
        ;;
    esac
done

if [ -n "${WHATSAPP_START_CONFIG_FILE:-}" ]; then
    if [ ! -f "$WHATSAPP_START_CONFIG_FILE" ]; then
        exit_with_err "Config file '$WHATSAPP_START_CONFIG_FILE' is not found or not file"
    fi
    set -a 
    # shellcheck disable=SC1090
    if ! source "$WHATSAPP_START_CONFIG_FILE"; then
        set +a
        exit_with_err "Cannot source '$WHATSAPP_START_CONFIG_FILE' with config envs" 
    fi
    set +a
fi

if [ -z "${WHATSAPP_HAPROXY_BIN:-}" ]; then
    WHATSAPP_HAPROXY_BIN="haproxy"
fi

if ! command -v "$WHATSAPP_HAPROXY_BIN" > /dev/null; then
    exit_with_err "haproxy '$WHATSAPP_HAPROXY_BIN' binary not found"
fi

if [ -z "${WHATSAPP_PROXY_CONFIG_FILE:-}" ]; then
    export WHATSAPP_PROXY_CONFIG_FILE="$haproxy_cfg_default"
fi

if [ ! -s "$WHATSAPP_PROXY_CONFIG_FILE" ]; then
    exit_with_err "Proxy config file '$WHATSAPP_PROXY_CONFIG_FILE' not found or is empty"
fi

if [ -z "${WHATSAPP_PROXY_CERT_FILE:-}" ]; then
    WHATSAPP_PROXY_CERT_FILE="/etc/haproxy/ssl/proxy.whatsapp.net.pem"
fi

if [ ! -s "${WHATSAPP_PROXY_CERT_FILE:-}" ]; then
    echo "Cert file '$WHATSAPP_PROXY_CERT_FILE' is not exists. Generate cert file"

    full_gen_cert_script="${working_dir}/generate-certs.sh"

    if [ ! -s "$full_gen_cert_script" ]; then
        exit_with_err "Gen cert script script '$full_gen_cert_script' is not found or empty"
    fi

    export tmp_cert_dir=""
    
    function cleanup_tmp_dir {
        if [ -n "$tmp_cert_dir" ] && [ -d "$tmp_cert_dir" ]; then
            rm -rf "$tmp_cert_dir"
            echo "'$tmp_cert_dir' removed"
        fi      
    }

    if ! tmp_cert_dir="$(mktemp -d)"; then
        exit_with_err "Cannot create temp dir for generating cert"
    fi

    if [ -z "$tmp_cert_dir" ] || [ ! -d "$tmp_cert_dir" ]; then
        exit_with_err "Temp cert dir '$tmp_cert_dir' is empty or not dir"
    fi

    trap 'cleanup_tmp_dir' EXIT
    trap 'cleanup_tmp_dir' SIGINT
    trap 'cleanup_tmp_dir' SIGTERM

    pushd "$tmp_cert_dir"
    
    if ! "$full_gen_cert_script"; then
        exit_with_err "Cannot generate cert"
    fi

    if [ ! -s "proxy.whatsapp.net.pem" ]; then
        exit_with_err "Cert file proxy.whatsapp.net.pem not found or empty"
    fi

    if ! mv proxy.whatsapp.net.pem "$WHATSAPP_PROXY_CERT_FILE"; then
        exit_with_err "Cannot move proxy.whatsapp.net.pem to '$WHATSAPP_PROXY_CERT_FILE'"
    fi
    
    if [ -n "${WHATSAPP_PROXY_CERT_FILE_CHOWN:-}" ]; then
        if ! chown "$WHATSAPP_PROXY_CERT_FILE_CHOWN" "$WHATSAPP_PROXY_CERT_FILE"; then
            exit_with_err "Cannot chown '$WHATSAPP_PROXY_CERT_FILE' to '$WHATSAPP_PROXY_CERT_FILE_CHOWN'"
        fi
    fi

    if ! chmod 600 "$WHATSAPP_PROXY_CERT_FILE"; then
        echo_err "Cannot chmod '$WHATSAPP_PROXY_CERT_FILE' to 600. Continue"
    fi
    
    popd
else
    echo "Cert file '$WHATSAPP_PROXY_CERT_FILE' exists. Skip generation"
fi

# Start HAProxy as the container's main process.
exec "$WHATSAPP_HAPROXY_BIN" -f "$WHATSAPP_PROXY_CONFIG_FILE"
