#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
#
# License found in the LICENSE file in the root directory
# of this source tree.

set -e

## Script envs
# HAPROXY_BIN - path to haproxy binary. Default: haproxy
# WHATSAPP_PROXY_CONFIG_FILE - path to ha proxy config. Default: /usr/local/etc/haproxy/haproxy.cfg
# WHATSAPP_PROXY_CERT_FILE - path to proxy tls key and cert. Default: /etc/haproxy/ssl/proxy.whatsapp.net.pem 
# WHATSAPP_PROXY_CERT_FILE_CHOWN - if passed will chown to cert file to passed string

## Config envs
# WHATSAPP_STATS_BIND_PORT - if passed bind to 127.0.0.1:${WHATSAPP_STATS_BIND_PORT} metrics server
# WHATSAPP_V4_HTTP_FRONTEND_BIND - http frontend bind string
#   Default - 127.0.0.1:80
# WHATSAPP_V4_HTTP_FRONTEND_ACCEPT_PROXY_BIND - if passed bind frontend with pass real ip for http
# WHATSAPP_V4_HTTPS_FRONTEND_BIND - http frontend bind string
#   Default - 127.0.0.1:443
# WHATSAPP_V4_HTTPS_FRONTEND_ACCEPT_PROXY_BIND - if passed bind frontend with pass real ip for https
# WHATSAPP_V4_XMPP_FRONTEND_BIND - xmpp frontend bind string
#   Default - 127.0.0.1:5222
# WHATSAPP_V4_XMPP_FRONTEND_ACCEPT_PROXY_BIND - if passed bind frontend with pass real ip for xmpp
# WHATSAPP_V4_NET_FRONTEND_BIND - whatsapp net frontend bind string
#   Default - 127.0.0.1:7777
# WHATSAPP_NET_DESTINATION - proxy destination for whatsapp net with tls
#   Default - whatsapp.net:443
# WHATSAPP_XMPP_DESTINATION - proxy destination for xmpp
#   Default - g.whatsapp.net:5222
# WHATSAPP_NET_HTTP_DESTINATION - proxy destination for whatsapp net without tls
#   Default - g.whatsapp.net:80

working_dir=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

if [ -z "$HAPROXY_BIN" ]; then
    HAPROXY_BIN="haproxy"
fi

if ! command "$HAPROXY_BIN" > /dev/null; then
    echo "haproxy '$HAPROXY_BIN' binary not found"
    exit 1
fi

if [ -z "$WHATSAPP_PROXY_CONFIG_FILE" ]; then
    export WHATSAPP_PROXY_CONFIG_FILE="/usr/local/etc/haproxy/haproxy.cfg"
fi

if [ ! -f "$WHATSAPP_PROXY_CONFIG_FILE" ]; then
    echo "Proxy config file '$WHATSAPP_PROXY_CONFIG_FILE' not found or not file"
    exit 1
fi

if [ ! -s "$WHATSAPP_PROXY_CONFIG_FILE" ]; then
    echo "Proxy config file '$WHATSAPP_PROXY_CONFIG_FILE' is empty"
    exit 1
fi

if [ -z "$WHATSAPP_PROXY_CERT_FILE" ]; then
    WHATSAPP_PROXY_CERT_FILE="/etc/haproxy/ssl/proxy.whatsapp.net.pem"
fi

if [ ! -s "$WHATSAPP_PROXY_CERT_FILE" ]; then
    echo "Cert file '$WHATSAPP_PROXY_CERT_FILE' is not exists. Generate cert file"

    full_gen_cert_script="${working_dir}/generate-certs.sh"

    if [ ! -s "$full_gen_cert_script" ]; then
        echo "Gen cert script script '$full_gen_cert_script' is not found or empty"
        exit 1
    fi

    export tmp_cert_dir=""
    
    function cleanup_tmp_dir {
        if [ -n "$tmp_cert_dir" ] && [ -d "$tmp_cert_dir" ]; then
            rm -rf "$tmp_cert_dir"
            echo "'$tmp_cert_dir' removed"
        fi      
    }

    if ! tmp_cert_dir="$(mktemp -d)"; then
        echo "Cannot create temp dir for generating cert"
        exit 1
    fi

    if [ -z "$tmp_cert_dir" ] || [ ! -d "$tmp_cert_dir" ]; then
        echo "Temp cert dir '$tmp_cert_dir' is empty or not dir"
        exit 1
    fi

    trap 'cleanup_tmp_dir' EXIT
    trap 'cleanup_tmp_dir' SIGINT
    trap 'cleanup_tmp_dir' SIGTERM

    pushd "$tmp_cert_dir"
    
    "$full_gen_cert_script"

    if ! mv proxy.whatsapp.net.pem "$WHATSAPP_PROXY_CERT_FILE"; then
        echo "Cannot move proxy.whatsapp.net.pem to '$WHATSAPP_PROXY_CERT_FILE'"
        exit 1
    fi
    
    if [ -n "$WHATSAPP_PROXY_CERT_FILE_CHOWN" ]; then
        if ! chown "$WHATSAPP_PROXY_CERT_FILE_CHOWN" "$WHATSAPP_PROXY_CERT_FILE"; then
            echo "Cannot chown '$WHATSAPP_PROXY_CERT_FILE' to '$WHATSAPP_PROXY_CERT_FILE_CHOWN'"
            exit 1
        fi
    fi
    
    popd
else
    echo "Cert file '$WHATSAPP_PROXY_CERT_FILE' exists. Skip generation"
fi

# Start HAProxy as the container's main process.
exec "$HAPROXY_BIN" -f "$WHATSAPP_PROXY_CONFIG_FILE"
