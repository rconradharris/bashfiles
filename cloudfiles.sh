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
    local cmd=$1

    if [[ -z $cmd ]]; then
        cmd='<ls|get|put|rm>'
    fi

    echo "$PROG $cmd [container] [object-name]"
    exit 1
}


function load_config() {
    local config=~/.$PROG
    if [[ -r $config ]]; then
        source $config
    fi
}


function check_code() {
    local code=$1

    if [ $code -lt 200 ] || [ $code -gt 299 ]; then
        echo "Invalid response code: $code"
        exit 1
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


function cf_ls() {
    local container=$1

    local url=$CF_MGMT_URL/$container
    local tmp_file=$(mktemp -t cloudfiles.sh)
    local code=$(curl --silent --fail --write-out '%{http_code}' \
                      --header "X-Auth-Token: $CF_AUTH_TOKEN" \
                      --output $tmp_file $url)
    check_code $code
    cat $tmp_file
    rm $tmp_file
}


function cf_get() {
    local container=$1
    local obj_name=$2

    if [[ -z $container || -z $obj_name ]]; then
        usage 'get'
    fi

    local filename=`basename $obj_name`
    local url=$CF_MGMT_URL/$container/$obj_name

    local code=$(curl --silent --fail --write-out '%{http_code}' \
                      --header "X-Auth-Token: $CF_AUTH_TOKEN" \
                      --output $filename $url)
    check_code $code
}


function cf_put() {
    local container=$1
    local filename=$2

    if [[ -z $container || -z $filename ]]; then
        usage 'put'
    fi

    local obj_name=`basename $filename`
    local content_type='application/octet-stream'
    local url=$CF_MGMT_URL/$container/$obj_name

    local code=$(curl --silent --fail --write-out '%{http_code}' \
                      --header "X-Auth-Token: $CF_AUTH_TOKEN" \
                      --request PUT --header "Content-Type: $content_type" \
                      --upload-file $filename $url)
    check_code $code
}


function cf_rm() {
    local container=$1
    local obj_name=$2

    if [[ -z $container || -z $obj_name ]]; then
        usage 'rm'
    fi

    local url=$CF_MGMT_URL/$container/$obj_name
    local code=$(curl --silent --fail --write-out '%{http_code}' \
                       --header "X-Auth-Token: $CF_AUTH_TOKEN" \
                       --request DELETE $url)
    check_code $code
}


load_config
cf_auth

case $1 in
    ls)
        cf_ls $2;;
    get)
        cf_get $2 $3;;
    put)
        cf_put $2 $3;;
    rm)
        cf_rm $2 $3;;
    *)
        usage;;
esac
