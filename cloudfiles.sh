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
CONFIG=~/.$PROG
COMPLETION_DIR=~/.$PROG-completion

DEFAULT_CF_AUTH_URL_US=https://auth.api.rackspacecloud.com/v1.0
DEFAULT_CF_AUTH_URL_UK=https://lon.auth.api.rackspacecloud.com/v1.0

OPT_SILENT=0
OPT_CONTENT_TYPE=


function cf_warn() {
    echo "warning: $@" >&2
}


function cf_die() {
    echo "$@" >&2
    exit 1
}


function cf_usage() {
    cf_die "usage: $PROG [-s|-t] $@"
}


function cf_general_usage() {
    cf_usage '<ls|get|mkdir|put|rm|rmdir|stat> [container] [object-name]'
}


function cf_load_config() {
    if [[ -r $CONFIG ]]; then
        source $CONFIG
    fi
}


function cf_ask() {
    local question=$1

    read -p "$question"
    echo $REPLY
}


function cf_ask_required() {
    local var=$1
    local question=$2
    local reply=`cf_ask "$question"`
    if [[ -z $reply ]]; then
        cf_die 'Aborted'
    fi
    eval $var="'$reply'"
}


function cf_ask_with_default() {
    local default=$1
    local question=$2

    local reply=`cf_ask "$question"`

    if [[ -z $reply ]]; then
        reply=$default
    fi

    echo "$reply"
}


function cf_save_config() {
    if [[ -e $CONFIG ]]; then
        cf_warn "Cannot save credentials, file $CONFIG already exists"
        return
    fi
    cat > $CONFIG <<EOF
CF_USER=$CF_USER
CF_API_KEY=$CF_API_KEY
CF_AUTH_URL=$CF_AUTH_URL
CF_SMART_COMPLETION=$CF_SMART_COMPLETION
EOF
}


function cf_retrieve_credentials() {
    local creds_updated=0

    # 1. Check config file
    # 2. Check environment
    # 3. Ask user
    # 4. Optional: Save credentials to config file
    cf_load_config

    if [[ -z $CF_USER ]]; then
        cf_ask_required 'CF_USER' 'CloudFiles Username: '
        creds_updated=1
    fi

    if [[ -z $CF_API_KEY ]]; then
        cf_ask_required 'CF_API_KEY' 'CloudFiles API Key: '
        creds_updated=1
    fi

    if [[ -z $CF_AUTH_URL ]]; then
        local auth_url=$(cf_ask_with_default us \
                         'Location or Auth URL: [<url>/uk/US]: ')

        if [[ $auth_url == 'uk' || $auth_url == 'UK' ]]; then
            CF_AUTH_URL=$DEFAULT_CF_AUTH_URL_UK
        elif [[ $auth_url == 'us' || $auth_url == 'US' ]]; then
            CF_AUTH_URL=$DEFAULT_CF_AUTH_URL_US
        else
            CF_AUTH_URL=$auth_url
        fi
    fi

    if [[ $creds_updated -eq 1 ]]; then
        # Only ask about smart completion if we were already asking for USER
        # or API_KEY
        if [[ -z $CF_SMART_COMPLETION ]]; then
            local smart_completion=$(cf_ask_with_default y \
                         'Enable container and object name completion [Y/n]? ')

            if [[ $smart_completion = 'y' || $smart_completion = 'Y' ]]; then
                CF_SMART_COMPLETION=1
            else
                CF_SMART_COMPLETION=0
            fi
        fi

        local save_creds=`cf_ask_with_default N 'Save settings [y/N]? '`

        if [[ $save_creds = 'y' || $save_creds = 'Y' ]]; then
            cf_save_config
        fi
    fi
}


function cf_mktemp() {
    echo `mktemp -t $PROG`
}


function cf_autodetect_filetype() {
    local filename=$1
    echo `file --brief --mime $filename`
}


function cf_auth() {
    if [[ -z $CF_AUTH_URL ]]; then
        CF_AUTH_URL=$DEFAULT_CF_AUTH_URL_US
    fi

    local auth_resp=$(
        curl --silent --fail --dump-header - \
             --header "X-Auth-Key: $CF_API_KEY" \
             --header "X-Auth-User: $CF_USER" \
             ${CF_AUTH_URL})

    CF_AUTH_TOKEN=$(echo "$auth_resp" | grep ^X-Auth-Token \
                                      | sed 's/.*: //' \
                                      | tr -d "\r\n")

    CF_MGMT_URL=$(echo "$auth_resp" | grep ^X-Storage-Url \
                                    | sed 's/.*: //' \
                                    | tr -d "\r\n")

    if [[ -z $CF_AUTH_TOKEN || -z $CF_MGMT_URL ]]; then
        echo "Unable to authenticate, set credentials in $CONFIG or" \
             " CF_USER and CF_API_KEY environment variables"
        exit 1
    fi
}


function cf_curl() {
    local opt_silent=

    if [[ $OPT_SILENT -ne 0 ]]; then
        local opt_silent=--silent
    fi

    local code=$(curl $opt_silent --fail --write-out '%{http_code}' \
                      --header "X-Auth-Token: $CF_AUTH_TOKEN" "$@")

    if [ $code -lt 200 ] || [ $code -gt 299 ]; then
        echo "Invalid response code: $code"
        exit 1
    fi
}


function cf_ls() {
    local container=$1
    local tmp_file=`cf_mktemp`

    OPT_SILENT=1

    cf_curl --output $tmp_file $CF_MGMT_URL/$container

    cat $tmp_file

    if [[ $CF_SMART_COMPLETION -eq 1 ]]; then
        if [[ -z $container ]]; then
            mv $tmp_file $COMPLETION_DIR/container-names
        else
            mv $tmp_file $COMPLETION_DIR/$container-object-names
        fi
    else
        rm $tmp_file
    fi
}


function cf_get() {
    local container=$1
    local obj_name=$2

    if [[ -z $container || -z $obj_name ]]; then
        cf_usage 'get <container> <object-name>'
    fi

    local filename=`basename $obj_name`
    cf_curl --output $filename $CF_MGMT_URL/$container/$obj_name
}


function cf_mkdir() {
    local container=$1

    if [[ -z $container ]]; then
        cf_usage 'mkdir <container>'
    fi

    OPT_SILENT=1

    cf_curl --request PUT --upload-file /dev/null $CF_MGMT_URL/$container
}


function cf_put() {
    local container=$1
    local filename=$2

    if [[ -z $container || -z $filename ]]; then
        cf_usage 'put <container> <object-name>'
    fi

    local obj_name=`basename $filename`

    if [[ -n $OPT_CONTENT_TYPE ]]; then
        local content_type=$OPT_CONTENT_TYPE
    else
        local content_type=`cf_autodetect_filetype $filename`
    fi

    cf_curl --request PUT --header "Content-Type: $content_type" \
            --upload-file $filename $CF_MGMT_URL/$container/$obj_name
}


function cf_rm() {
    local container=$1
    local obj_name=$2

    if [[ -z $container || -z $obj_name ]]; then
        cf_usage 'rm <container> <object-name>'
    fi

    OPT_SILENT=1

    cf_curl --request DELETE $CF_MGMT_URL/$container/$obj_name
}


function cf_rmdir() {
    local container=$1

    if [[ -z $container ]]; then
        cf_usage 'rmdir <container>'
    fi

    OPT_SILENT=1

    cf_curl --request DELETE $CF_MGMT_URL/$container
}


function cf_stat() {
    local container=$1
    local obj_name=$2

    local tmp_file=`cf_mktemp`

    OPT_SILENT=1

    # NOTE: if we used --request HEAD instead of --head, curl would expect
    # Content-Length bytes to be sent as entity body which would cause a
    # timeout since HEAD requests don't result in a body
    cf_curl --output /dev/null --head --dump-header $tmp_file \
            $CF_MGMT_URL/$container/$obj_name

    cat $tmp_file
    rm $tmp_file
}


function cf_init() {
    cf_retrieve_credentials
    cf_auth

    if [[ $CF_SMART_COMPLETION -eq 1 && ! -d $COMPLETION_DIR ]]; then
        mkdir $COMPLETION_DIR
    fi
}


function cf_bash_completer() {
    local cur=$1
    local prev=$2
    local cmds='ls get mkdir put rm rmdir stat'

    # Commands
    if [[ $PROG =~ $cur ]]; then
        echo $cmds
        return
    fi

    local container_names=`cat $COMPLETION_DIR/container-names | tr '\n' ' '`

    # Container Names
    if [[ $cmds =~ $cur || $cmds =~ $prev ]]; then
        echo $container_names
        return
    fi

    # Object Names
    if [[ $container_names =~ $cur ]]; then
        local container=$cur
    elif [[ $container_names =~ $prev ]]; then
        local container=$prev
    else
        local container=
    fi

    if [[ -n $container ]]; then
        local obj_filename=$COMPLETION_DIR/$container-object-names
        if [[ -r $obj_filename ]]; then
            echo `cat $obj_filename | tr '\n' ' '`
            return
        fi
    fi
}


#############################################################################
#                                                                           #
#                                    Main                                   #
#                                                                           #
#############################################################################


while getopts 'st:' opt; do
    case $opt in
        s)
            OPT_SILENT=1;;
        t)
            OPT_CONTENT_TYPE=$OPTARG;;
        *)
            cf_general_usage;;
    esac
done

shift $(($OPTIND - 1))

case $1 in
    ls)
        cf_init
        cf_ls $2;;
    get)
        cf_init
        cf_get $2 $3;;
    mkdir)
        cf_init
        cf_mkdir $2;;
    put)
        cf_init
        cf_put $2 $3;;
    rm)
        cf_init
        cf_rm $2 $3;;
    rmdir)
        cf_init
        cf_rmdir $2;;
    stat)
        cf_init
        cf_stat $2 $3;;
    _bash_completer)
        cf_bash_completer $2 $3;;
    *)
        cf_general_usage;;
esac
