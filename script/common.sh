#!/bin/bash
# shellcheck disable=SC2034
# shellcheck disable=SC2155
set +o noglob

URL_GH_PROXY='https://gh-proxy.com/'
URL_CLASH_UI="http://board.zash.run.place"

RESOURCES_BASE_DIR='./resources'
RESOURCES_CONFIG="${RESOURCES_BASE_DIR}/config.yaml"

ZIP_BASE_DIR="${RESOURCES_BASE_DIR}/zip"
ZIP_CLASH="${ZIP_BASE_DIR}/clash*.gz"
ZIP_MIHOMO="${ZIP_BASE_DIR}/mihomo*.gz"
ZIP_YQ="${ZIP_BASE_DIR}/yq*.tar.gz"
ZIP_CONVERT="${ZIP_BASE_DIR}/subconverter*.tar.gz"
ZIP_UI="${ZIP_BASE_DIR}/yacd.tar.xz"

CLASH_BASE_DIR='/opt/clash'
CLASH_CONFIG_URL="${CLASH_BASE_DIR}/url"
CLASH_CONFIG_RAW="${CLASH_BASE_DIR}/config.yaml"
CLASH_CONFIG_RAW_BAK="${CLASH_CONFIG_RAW}.bak"
CLASH_CONFIG_MIXIN="${CLASH_BASE_DIR}/mixin.yaml"
CLASH_CONFIG_RUNTIME="${CLASH_BASE_DIR}/runtime.yaml"
CLASH_UPDATE_LOG="${CLASH_BASE_DIR}/clashupdate.log"

BIN_BASE_DIR="${CLASH_BASE_DIR}/bin"
BIN_CLASH="${BIN_BASE_DIR}/clash"
BIN_MIHOMO="${BIN_BASE_DIR}/mihomo"
BIN_YQ="${BIN_BASE_DIR}/yq"
BIN_SUBCONVERTER="${BIN_BASE_DIR}/subconverter/subconverter"

# 默认集成、安装mihomo内核
# 删除mihomo/系统非amd64：下载安装clash内核
# shellcheck disable=SC2086
# shellcheck disable=SC2015
function _get_kernel() {
    local cpu_arch=$(uname -m)
    {
        [ "$cpu_arch" = 'x86_64' ] &&
            /bin/ls $ZIP_BASE_DIR 2>/dev/null | grep -E 'clash|mihomo' | grep -qs 'amd64'
    } || {
        /bin/rm -rf $ZIP_KERNEL
        _download_clash "$cpu_arch"
    }

    [ -e $ZIP_MIHOMO ] && {
        ZIP_KERNEL=$ZIP_MIHOMO
        BIN_KERNEL=$BIN_MIHOMO
    } || {
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }
}

function _get_os() {
    local os_info=$(cat /etc/os-release)
    echo "$os_info" | grep -iqsE "rhel|centos" && {
        CLASH_CRON_TAB='/var/spool/cron/root'
        BASHRC='/etc/bashrc'
    }
    echo "$os_info" | grep -iqsE "debian|ubuntu" && {
        CLASH_CRON_TAB='/var/spool/cron/crontabs/root'
        BASHRC='/etc/bash.bashrc'
    }
}

function _get_port() {
    local mixed_port=$(sudo $BIN_YQ '.mixed-port // ""' $CLASH_CONFIG_RUNTIME)
    local ext_addr=$(sudo $BIN_YQ '.external-controller // ""' $CLASH_CONFIG_RUNTIME)
    local ext_port=${ext_addr##*:}

    MIXED_PORT=${mixed_port:-7890}
    UI_PORT=${ext_port:-9090}

    # 端口占用场景
    _random_port() {
        local randomPort
        while :; do
            randomPort=$((RANDOM % 64512 + 1024))
            grep -q "$(printf ":%04X" $randomPort)" /proc/net/tcp || {
                echo $randomPort
                break
            }
        done
    }
    local arg
    for arg in $MIXED_PORT $UI_PORT; do
        sudo awk '{print $2}' /proc/net/tcp | grep -qsi ":$(printf "%x" "$arg")" && {
            [ "$arg" = "$MIXED_PORT" ] && {
                local newPort=$(_random_port)
                local msg="端口占用：${MIXED_PORT}，随机分配：$newPort"
                sudo "$BIN_YQ" -i ".mixed-port = $newPort" $CLASH_CONFIG_RUNTIME
                MIXED_PORT=$newPort
                _failcat "$msg"
                continue
            }
            [ "$arg" = "$UI_PORT" ] && {
                newPort=$(_random_port)
                msg="端口占用：$UI_PORT，随机分配：$newPort"
                sudo "$BIN_YQ" -i ".external-controller = \"0.0.0.0:$newPort\"" $CLASH_CONFIG_RUNTIME
                UI_PORT=$newPort
                _failcat "$msg"
            }
        }
    done
}

function _color() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf "\e[38;2;%d;%d;%dm" "$r" "$g" "$b"
}

function _color_msg() {
    local color=$(_color "$1")
    local msg=$2
    local reset="\033[0m"
    printf "%b%s%b\n" "$color" "$msg" "$reset"
}

function _okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_msg "$color" "$msg" && return 0
}

function _failcat() {
    local color=#FFD700
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _color_msg "$color" "$msg" && return 1
}

# bash执行   $0为脚本执行路径
# source执行 $0为bash
function _error_quit() {
    local color=#f92f60
    local msg="❌ $1"
    _color_msg "$color" "$msg"
    echo "$0" | grep -qs 'bash' && exec bash || exit 1
}

_download_clash() {
    local url sha256sum
    case "$1" in
    x86_64)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-amd64-2023.08.17.gz
        sha256sum='92380f053f083e3794c1681583be013a57b160292d1d9e1056e7fa1c2d948747'
        ;;
    *86*)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-386-2023.08.17.gz
        sha256sum='254125efa731ade3c1bf7cfd83ae09a824e1361592ccd7c0cccd2a266dcb92b5'
        ;;
    armv*)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-armv5-2023.08.17.gz
        sha256sum='622f5e774847782b6d54066f0716114a088f143f9bdd37edf3394ae8253062e8'
        ;;
    aarch64)
        url=https://downloads.clash.wiki/ClashPremium/clash-linux-arm64-2023.08.17.gz
        sha256sum='c45b39bb241e270ae5f4498e2af75cecc0f03c9db3c0db5e55c8c4919f01afdd'
        ;;
    *)
        _error_quit "未知的架构版本：$1，请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
        ;;
    esac
    _failcat "当前CPU架构为：$1，正在下载对应版本..."
    wget --timeout=30 \
        --tries=1 \
        --no-check-certificate \
        --directory-prefix "$ZIP_BASE_DIR" \
        "$url"
    # shellcheck disable=SC2086
    echo $sha256sum $ZIP_CLASH | sha256sum -c ||
        _error_quit "下载失败：请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"

}

function _valid_env() {
    [ "$(whoami)" != "root" ] && _error_quit "需要 root 或 sudo 权限执行"
    [ "$(ps -p $$ -o comm=)" != "bash" ] && _error_quit "当前终端不是 bash"
    [ "$(ps -p 1 -o comm=)" != "systemd" ] && _error_quit "系统不具备 systemd"
}

function _valid_config() {
    [ -e "$1" ] && [ "$(wc -l <"$1")" -gt 1 ] && {
        local test_cmd="$BIN_KERNEL -d $(dirname "$1") -f $1 -t"
        $test_cmd >/dev/null || {
            $test_cmd >&2 | grep -qs "unsupport proxy type" &&
                _error_quit "不支持的代理协议，请安装 mihomo 内核"
        }
    }
}

function _download_config() {
    local url=$1
    local dest=$2
    local agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0'
    sudo curl \
        --silent \
        --show-error \
        --insecure \
        --connect-timeout 4 \
        --retry 1 \
        --user-agent "$agent" \
        --output "$dest" \
        "$url" ||
        sudo wget \
            --no-verbose \
            --no-check-certificate \
            --timeout 3 \
            --tries 1 \
            --user-agent "$agent" \
            --output-document "$dest" \
            "$url"
}

_convert_url() {
    local raw_url="$1"
    local base_url="http://127.0.0.1:25500/sub?target=clash&url="

    urlencode() {
        local LANG=C
        local length="${#1}"
        for ((i = 0; i < length; i++)); do
            c="${1:i:1}"
            case "$c" in
            [a-zA-Z0-9.~_-]) printf "%s" "$c" ;;
            *) printf '%%%02X' "'$c" ;;
            esac
        done
        echo
    }

    local encoded_url=$(urlencode "$raw_url")
    echo "${base_url}${encoded_url}"
}

_start_convert() {
    # 子shell运行，屏蔽kill时的输出
    (sudo $BIN_SUBCONVERTER >&/dev/null &)
    local start=$(date +%s%3N)
    while ! sudo lsof -i :25500 >&/dev/null; do
        sleep 0.05
        local now=$(date +%s%3N)
        [ $(("$now" - "$start")) -gt 500 ] && _error_quit '订阅转换服务未启动，请检查25500端口是否被占用'
    done
}

_stop_convert() {
    pkill -9 -f subconverter >&/dev/null
}

function _download_convert_config() {
    local url=$1
    local dest=$2
    _start_convert
    _download_config "$(_convert_url "$url")" "$dest"
    _stop_convert
}
