#!/bin/bash
# cloudfiles.sh - Mange CloudFiles via the command-line

VERSION=0.1
PROG=`basename $0`
CONFIG=~/.$PROG
COMPLETION_DIR=~/.$PROG-completion

DEFAULT_CF_AUTH_URL_US=https://auth.api.rackspacecloud.com/v1.0
DEFAULT_CF_AUTH_URL_UK=https://lon.auth.api.rackspacecloud.com/v1.0

CF_SEGMENT_SIZE=5368709120
DD_BLOCK_SIZE=1024

OPT_CONTENT_TYPE=
OPT_FORCE=0
OPT_OUTPUT=
OPT_QUIET=0
OPT_SERVICENET=0

CONST_ZERO_MD5=d41d8cd98f00b204e9800998ecf8427e


function cf_log() {
    if [[ $OPT_QUIET -eq 0 ]]; then
        echo "$@" >&2
    fi
}


function cf_warn() {
    echo "warning: $@" >&2
}


function cf_error() {
    echo "error: $@" >&2
}


function cf_die() {
    echo "$@" >&2
    exit 1
}


function cf_usage() {
    cf_die "usage: $PROG [-fhqstv] $@"
}


function cf_general_usage() {
    cf_usage '<cp|get|ls|mkdir|mv|put|rm|rmdir|stat> [container] [object-name]'
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
CF_SERVICENET=$CF_SERVICENET
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

    if [[ -z $CF_SERVICENET ]]; then
        local snet=`cf_ask_with_default n 'Use ServiceNET [y/N]? '`

        if [[ $snet = 'y' || $snet = 'Y' ]]; then
            CF_SERVICENET=1
        else
            CF_SERVICENET=0
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


function cf_md5() {
    if [[ -e /sbin/md5 ]]; then
        # OSX
        echo `md5 -q $1`
    else
        # Linux
        echo `md5sum -q $1`
    fi
}


function cf_mktemp() {
    echo `mktemp -t $PROG`
}


function cf_size() {
    local filename=$1

    if stat -c 2>&1 | grep -q illegal; then
        # Mac OS X
        echo `stat -f%z ${filename}`
    else
        # Linux
        echo `stat -c%s ${filename}`
    fi
}


function cf_compute_num_blocks() {
    local total_size=$1
    local block_size=$2

    let nblocks=$total_size/$block_size
    let reminader=$total_size%$block_size

    if [[ $remainder -gt 0 ]]; then
        let nblocks++
    fi

    echo $nblocks
}


function cf_autodetect_filetype() {
    local filename=$1
    echo `file --brief --mime $filename`
}


function cf_handle_snet() {
    if [[ $OPT_SERVICENET -eq 1 || $CF_SERVICENET -eq 1 ]]; then
        CF_STORAGE_URL=${CF_STORAGE_URL/https:\/\//https://snet-}
        CF_STORAGE_URL=${CF_STORAGE_URL/http:\/\//http://snet-}
    fi
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

    CF_STORAGE_URL=$(echo "$auth_resp" | grep ^X-Storage-Url \
                                       | sed 's/.*: //' \
                                       | tr -d "\r\n")

    if [[ -z $CF_AUTH_TOKEN || -z $CF_STORAGE_URL ]]; then
        echo "Unable to authenticate, set credentials in $CONFIG or" \
             " CF_USER and CF_API_KEY environment variables"
        exit 1
    fi

    cf_handle_snet
}


function cf_check_code() {
    local code=$1

    if [[ $code -lt 200 || $code -gt 299 ]]; then
        echo "Invalid response code: $code"
        exit 1
    fi
}


function cf_curl() {
    local code=$(curl --fail --write-out '%{http_code}' \
                      --header "X-Auth-Token: $CF_AUTH_TOKEN" "$@")

    cf_check_code $code
}


function cf_cp() {
    local src_container=$1
    local src_obj_name=$2
    local dst_container=$3
    local dst_obj_name=$4

    if [[ -z $src_container || -z $src_obj_name
                            || -z $dst_container \
                            || -z $dst_obj_name ]]; then
        cf_usage 'cp <src-container> <src-object-name>' \
                 ' <dst-container> <dst-object-name>'
    fi

    cf_init
    cf_curl --silent --request COPY \
            --header "Destination: /$dst_container/$dst_obj_name" \
            $CF_STORAGE_URL/$src_container/$src_obj_name
}


function cf_ls() {
    local container=$1
    local tmp_file=`cf_mktemp`

    cf_init
    cf_curl --silent --output $tmp_file $CF_STORAGE_URL/$container

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
    shift
    local obj_names=$@

    if [[ -z $container || -z $obj_names ]]; then
        cf_usage 'get <container> <object-names>'
    fi

    cf_init

    for obj_name in $obj_names; do
        if [[ -n $OPT_OUTPUT ]]; then
            local filename=$OPT_OUTPUT
        else
            local filename=`basename $obj_name`
        fi

        if [[ $filename == - ]]; then
            curl --fail --silent \
                 --header "X-Auth-Token: $CF_AUTH_TOKEN" \
                 $CF_STORAGE_URL/$container/$obj_name
            continue
        fi

        local output=.$filename.download

        if [[ $OPT_QUIET -eq 1 ]]; then
            local opt_silent=--silent
        else
            local opt_silent=
        fi

        local tmp_headers=`cf_mktemp`

        cf_curl $opt_silent --dump-header $tmp_headers --output $output \
                $CF_STORAGE_URL/$container/$obj_name

        local etag=$(cat $tmp_headers | grep --ignore-case ^Etag \
                                      | sed 's/.*: //' \
                                      | tr -d "\r\n" \
                                      | tr -d '"')

        if [[ -z `grep --ignore-case X-Object-Manifest $tmp_headers` ]]; then
            local dlo=0
        else
            # NOTE: Dynamic Large Objects won't have an ETag that matches
            local dlo=1
        fi

        rm $tmp_headers

        if [[ $output == - ]]; then
            true
        elif [[ $etag == $CONST_ZERO_MD5 ]]; then
            # NOTE: If it's a 0-byte file, curl will not create the output
            # file, so we have to do that ourselves
            touch $filename
            cf_warn "Zero-byte file created"
        elif [[ $dlo -eq 1 || $etag == `cf_md5 $output` ]]; then
            mv $output $filename
        else
            rm $output
            cf_die "ERROR: Failed checksum validation."
        fi
    done
}


function cf_mkdir() {
    local containers=$@

    if [[ -z $containers ]]; then
        cf_usage 'mkdir <containers>'
    fi

    cf_init

    for container in $containers; do
        cf_curl --silent --output /dev/null --request PUT \
                --upload-file /dev/null \
                $CF_STORAGE_URL/$container
    done
}


function cf_mv() {
    local src_container=$1
    local src_obj_name=$2
    local dst_container=$3
    local dst_obj_name=$4

    if [[ -z $src_container || -z $src_obj_name
                            || -z $dst_container \
                            || -z $dst_obj_name ]]; then
        cf_usage 'mv <src-container> <src-object-name>' \
                 ' <dst-container> <dst-object-name>'
    fi

    cf_cp $src_container $src_obj_name $dst_container $dst_obj_name

    # FIXME: only remove if copy was successful
    cf_rm $src_container $src_obj_name
}


function cf_put_small_object() {
    local container=$1
    local filename=$2
    local obj_name=$3
    local content_type=$4
    local size=$5

    local etag=`cf_md5 $filename`

    if [[ $OPT_QUIET -eq 1 ]]; then
        local opt_silent=--silent
    else
        local opt_silent=
    fi

    cf_curl --request PUT --header "Content-Type: $content_type" \
            --header "ETag: $etag" --upload-file $filename \
            $opt_silent $CF_STORAGE_URL/$container/$obj_name
}


function cf_put_large_object() {
    local container=$1
    local filename=$2
    local obj_name=$3
    local content_type=$4
    local size=$5

    local left=$size
    local segment_num=1
    local skip=0

    if [[ $OPT_QUIET -eq 1 ]]; then
        local opt_silent=--silent
    else
        local opt_silent=
    fi
    local segments_container=${obj_name}_segments
    local obj_prefix="$segments_container/$obj_name/`date +%s`/$size/"

    cf_mkdir ${segments_container}

    local total_segments=`cf_compute_num_blocks $size $CF_SEGMENT_SIZE`

    while [[ $left -gt 0 ]]; do
        if [[ $left -ge $CF_SEGMENT_SIZE ]]; then
            local length=$CF_SEGMENT_SIZE
        else
            local length=$left
        fi

        local nblocks=`cf_compute_num_blocks $length $DD_BLOCK_SIZE`

        cf_log "Uploading segment $segment_num/$total_segments"
        # FIXME: unify this with cf_curl
        local code=$(
            dd if=$filename bs=$DD_BLOCK_SIZE count=$nblocks skip=$skip \
                2> /dev/null | \
            curl --fail --write-out '%{http_code}' $opt_silent \
                 --header "X-Auth-Token: $CF_AUTH_TOKEN" \
                 --upload-file - --request PUT \
                 --header "Transfer-Encoding: chunked" \
                 --header "Content-Type: $content_type" \
                 $CF_STORAGE_URL/$obj_prefix$(printf "%08d" $segment_num))

        cf_check_code $code

        cf_log ""

        let left-=$length
        let skip+=$nblocks
        let segment_num++
    done

    cf_log "Uploading manifest for ${filename}"
    cf_curl --data-binary '' --output /dev/null --request PUT \
            --header "Content-Type: ${content_type}" \
            --header "X-Object-Manifest: ${obj_prefix}" \
            $opt_silent ${CF_STORAGE_URL}/${container}/${obj_name}
}


function cf_put() {
    local container=$1
    shift
    local filenames=$@

    local ret=0

    if [[ -z $container || -z $filenames ]]; then
        cf_usage 'put <container> <filenames>'
    fi

    cf_init

    for filename in $filenames; do
        if [[ ! -e $filename ]]; then
            cf_error "File not found: $filename"
            ret=1
            continue
        fi

        local obj_name=`basename $filename`

        if [[ -n $OPT_CONTENT_TYPE ]]; then
            local content_type=$OPT_CONTENT_TYPE
        else
            local content_type=`cf_autodetect_filetype $filename`
        fi

        local size=`cf_size $filename`

        if [[ $size -gt $CF_SEGMENT_SIZE ]]; then
            cf_put_large_object $container $filename $obj_name "$content_type" $size
        else
            cf_put_small_object $container $filename $obj_name "$content_type" $size
        fi
    done

    return $ret
}


function cf_rm() {
    local container=$1
    shift
    local obj_names=$@

    if [[ -z $container || -z $obj_names ]]; then
        cf_usage 'rm <container> <object-names>'
    fi

    cf_init

    for obj_name in $obj_names; do
        cf_curl --silent --request DELETE $CF_STORAGE_URL/$container/$obj_name
    done
}


function cf_clear_container() {
    local container=$1

    # TODO: handle pagination
    local obj_names=`cf_ls $container`

    # NOTE: tr -d is needed for Mac OS X, since wc -w has leading spaces
    # in output
    local total_objects=`echo $obj_names | wc -w | tr -d ' '`
    local idx=1

    for obj_name in $obj_names; do
        cf_log "Deleting $idx/$total_objects: $obj_name"
        let idx++
        cf_rm $container $obj_name
    done
}


function cf_rmdir() {
    local containers=$@

    if [[ -z $containers ]]; then
        cf_usage 'rmdir <containers>'
    fi

    cf_init

    for container in $containers; do
        if [[ $OPT_FORCE -eq 1 ]]; then
            cf_clear_container $container
        fi

        cf_curl --silent --request DELETE $CF_STORAGE_URL/$container
    done
}


function cf_stat() {
    local container=$1
    local obj_name=$2

    local tmp_file=`cf_mktemp`

    cf_init

    # NOTE: if we used --request HEAD instead of --head, curl would expect
    # Content-Length bytes to be sent as entity body which would cause a
    # timeout since HEAD requests don't result in a body
    cf_curl --silent --output /dev/null --head --dump-header $tmp_file \
            $CF_STORAGE_URL/$container/$obj_name

    cat $tmp_file
    rm $tmp_file
}


function cf_init() {
    if [[ -n $CF_AUTH_TOKEN ]]; then
        return
    fi

    cf_retrieve_credentials
    cf_auth

    if [[ $CF_SMART_COMPLETION -eq 1 && ! -d $COMPLETION_DIR ]]; then
        mkdir $COMPLETION_DIR
    fi
}


function cf_bash_completer() {
    local cur=$1
    local prev=$2
    local cmds='cp get ls mkdir mv put rm rmdir stat'

    # Commands
    if [[ $cur = $PROG || $prev = $PROG  ]]; then
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


function cf_version() {
    echo $VERSION
    exit 0
}


function cf_help() {
    cat <<EOF
SYNOPSIS

    $PROG [options] [commands] [container] [object-names]

DESCRIPTION

    $PROG is a utility for working with Rackspace CloudFiles via the
    command-line. $PROG has minimal dependencies, requiring only bash, curl,
    and a few other POSIX utilities.

    You can pass settings to $PROG via environment variables or by defining a
    configuration file located at ~/.cloudfiles.sh.

    $PROG supports bash-completion against commands, container and
    object-names, and can be enabled with the CF_SMART_COMPLETION=1 setting.

OPTIONS

    -h      Print help
    -f      Force (for rmdir this will remove all objects first)
    -o      Output filename ('-' to output to stdout)
    -q      Quiet mode (suppress progress meter)
    -s      Use Rackspace's ServiceNET network
    -t      Specify Content-Type for an upload (autodetect by default)
    -v      Print version

COMMANDS

    cp      Server-side object copy
    get     Download file
    ls      List all containers or contents of a specific container
    mkdir   Create a container
    mv      Server-side object move
    put     Upload file
    rmdir   Remove a container (-f to clear it first)
    stat    Account, container, or object information

SETTINGS

    CF_USER         CloudFiles username
    CF_API_KEY      CloudFiles API Key
    CF_AUTH_URL     CloudFiles authentication URL
    CF_SERVICENET   Use Rackspace's ServiceNET network
    CF_SMART_COMPLETION 
                    Whether to enable bash completion against object and
                    container-names

FILES

    ~/.cloudfiles.sh
    ~/.cloudfiles.sh-completion

AUTHORS

    Rick Harris
    Mike Barton
    Chmouel Boudjnah
    Jay Payne

BUGS

    Report to https://github.com/rconradharris/cloudfiles2.sh
EOF
    exit 0
}


#############################################################################
#                                                                           #
#                                    Main                                   #
#                                                                           #
#############################################################################


while getopts 'fho:qst:v' opt; do
    case $opt in
        f)
            OPT_FORCE=1;;
        h)
            cf_help;;
        o)
            OPT_OUTPUT=$OPTARG;;
        q)
            OPT_QUIET=1;;
        s)
            OPT_SERVICENET=1;;
        t)
            OPT_CONTENT_TYPE=$OPTARG;;
        v)
            cf_version;;
        *)
            cf_general_usage;;
    esac
done

shift $(($OPTIND - 1))

cmd=$1

shift

case $cmd in
    cp)
        cf_cp $@;;
    ls)
        cf_ls $@;;
    get)
        cf_get $@;;
    mkdir)
        cf_mkdir $@;;
    mv)
        cf_mv $@;;
    put)
        cf_put $@;;
    rm)
        cf_rm $@;;
    rmdir)
        cf_rmdir $@;;
    stat)
        cf_stat $@;;
    _bash_completer)
        cf_bash_completer $@;;
    *)
        cf_general_usage;;
esac
