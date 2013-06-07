#!/bin/bash
#
# Simple script to upload/download from CloudFiles written in bash.
#
# Based entirely on Mike Barton's excellent cloudfiles.sh
# (https://github.com/redbo/cloudfiles.sh) script w/ the following small
# changes:
#
#       * Config file support (so you don't have to type credentials every
#         time)
#
#       * Lowercase command names (easier to type)
#
PROG=`basename $0`

function usage() {
    echo "usage: $PROG $@" >&2
    exit 1
}


function load_config() {
    local config=~/.$PROG
    if [[ -r $config ]]; then
        source $config
    fi
}


function cf_auth() {
    CF_AUTH_URL=https://auth.api.rackspacecloud.com/v1.0

    local auth_resp=$(
        curl --silent --fail --dump-header - \
             --header "X-Auth-Key: $CF_API_KEY" \
             --header "X-Auth-User: $CF_USER" \
             ${CF_AUTH_URL})

    CF_AUTH_TOKEN=`echo "$auth_resp" | grep ^X-Auth-Token | sed 's/.*: //' | tr -d "\r\n"`
    CF_MGMT_URL=`echo "$auth_resp" | grep ^X-Storage-Url | sed 's/.*: //' | tr -d "\r\n"`

    if [ -z $CF_AUTH_TOKEN ] || [ -z $CF_MGMT_URL ]; then
        echo Unable to authenticate, set credentials in ~/.bashrc or \
             CF_USER and CF_API_KEY environment variables
        exit 1
    fi
}


function cf_curl() {
    local code=$(curl --silent --fail --write-out '%{http_code}' \
                      --header "X-Auth-Token: $CF_AUTH_TOKEN" "$@")

    if [ $code -lt 200 ] || [ $code -gt 299 ]; then
        echo "Invalid response code: $code"
        exit 1
    fi
}


function cf_ls() {
    local container=$1
    local tmp_file=$(mktemp -t cloudfiles.sh)

    cf_curl --output $tmp_file $CF_MGMT_URL/$container

    cat $tmp_file
    rm $tmp_file
}


function cf_get() {
    local container=$1
    local obj_name=$2

    if [[ -z $container || -z $obj_name ]]; then
        usage 'get <container> <object-name>'
    fi

    local filename=`basename $obj_name`
    cf_curl --output $filename $CF_MGMT_URL/$container/$obj_name
}


function cf_mkdir() {
    local container=$1

    if [[ -z $container ]]; then
        usage 'mkdir <container>'
    fi

    cf_curl --request PUT --upload-file /dev/null $CF_MGMT_URL/$container
}


function cf_put() {
    local container=$1
    local filename=$2

    if [[ -z $container || -z $filename ]]; then
        usage 'put <container> <object-name>'
    fi

    local obj_name=`basename $filename`
    local content_type='application/octet-stream'
    cf_curl --request PUT --header "Content-Type: $content_type" \
            --upload-file $filename $CF_MGMT_URL/$container/$obj_name
}


function cf_rm() {
    local container=$1
    local obj_name=$2

    if [[ -z $container || -z $obj_name ]]; then
        usage 'rm <container> <object-name>'
    fi

    cf_curl --request DELETE $CF_MGMT_URL/$container/$obj_name
}


function cf_rmdir() {
    local container=$1

    if [[ -z $container ]]; then
        usage 'rmdir <container>'
    fi

    cf_curl --request DELETE $CF_MGMT_URL/$container
}


load_config
cf_auth

case $1 in
    ls)
        cf_ls $2;;
    get)
        cf_get $2 $3;;
    mkdir)
        cf_mkdir $2;;
    put)
        cf_put $2 $3;;
    rm)
        cf_rm $2 $3;;
    rmdir)
        cf_rmdir $2;;
    *)
        usage '<ls|get|mkdir|put|rm|rmdir> [container] [object-name]';;
esac
