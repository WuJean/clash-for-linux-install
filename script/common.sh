#!/bin/bash
# shellcheck disable=SC2034
# shellcheck disable=SC2155
[ -n "$BASH_VERSION" ] && set +o noglob
[ -n "$ZSH_VERSION" ] && setopt glob

URL_GH_PROXY='https://gh-proxy.com/'
URL_CLASH_UI="http://board.zash.run.place"

SCRIPT_BASE_DIR='./script'

RESOURCES_BASE_DIR='./resources'
RESOURCES_CONFIG="${RESOURCES_BASE_DIR}/config.yaml"
RESOURCES_CONFIG_MIXIN="${RESOURCES_BASE_DIR}/mixin.yaml"

ZIP_BASE_DIR="${RESOURCES_BASE_DIR}/zip"
ZIP_CLASH="${ZIP_BASE_DIR}/clash*.gz"
ZIP_MIHOMO="${ZIP_BASE_DIR}/mihomo*.gz"
ZIP_YQ="${ZIP_BASE_DIR}/yq*.tar.gz"
ZIP_SUBCONVERTER="${ZIP_BASE_DIR}/subconverter*.tar.gz"
ZIP_UI="${ZIP_BASE_DIR}/yacd.tar.xz"

CLASH_BASE_DIR='/opt/clash'
CLASH_SCRIPT_DIR="${CLASH_BASE_DIR}/$(basename $SCRIPT_BASE_DIR)"
CLASH_CONFIG_URL="${CLASH_BASE_DIR}/url"
CLASH_CONFIG_RAW="${CLASH_BASE_DIR}/$(basename $RESOURCES_CONFIG)"
CLASH_CONFIG_RAW_BAK="${CLASH_CONFIG_RAW}.bak"
CLASH_CONFIG_MIXIN="${CLASH_BASE_DIR}/$(basename $RESOURCES_CONFIG_MIXIN)"
CLASH_CONFIG_RUNTIME="${CLASH_BASE_DIR}/runtime.yaml"
CLASH_UPDATE_LOG="${CLASH_BASE_DIR}/clashupdate.log"

BIN_BASE_DIR="${CLASH_BASE_DIR}/bin"
BIN_CLASH="${BIN_BASE_DIR}/clash"
BIN_MIHOMO="${BIN_BASE_DIR}/mihomo"
BIN_YQ="${BIN_BASE_DIR}/yq"
BIN_SUBCONVERTER_DIR="${BIN_BASE_DIR}/subconverter"
BIN_SUBCONVERTER_CONFIG="$BIN_SUBCONVERTER_DIR/pref.yml"
BIN_SUBCONVERTER_PORT="25500"
BIN_SUBCONVERTER="${BIN_SUBCONVERTER_DIR}/subconverter"
BIN_SUBCONVERTER_LOG="${BIN_SUBCONVERTER_DIR}/latest.log"

_get_var() {
    # 定时任务路径
    {
        local os_info=$(cat /etc/os-release)
        echo "$os_info" | grep -iqsE "rhel|centos" && {
            CLASH_CRON_TAB="/var/spool/cron/root"
        }
        echo "$os_info" | grep -iqsE "debian|ubuntu" && {
            CLASH_CRON_TAB="/var/spool/cron/crontabs/root"
        }
    }
    # rc文件路径
    {
        local home=$HOME
        [ -n "$SUDO_USER" ] && home=$(awk -F: -v user="$SUDO_USER" '$1==user{print $6}' /etc/passwd)

        BASH_RC_ROOT='/root/.bashrc'
        BASH_RC_USER="${home}/.bashrc"
    }
    # 内核bin路径
    {
        [ -f "$BIN_MIHOMO" ] && {
            BIN_KERNEL=$BIN_MIHOMO
        }
        [ -f "$BIN_CLASH" ] && {
            BIN_KERNEL=$BIN_CLASH
        }
        BIN_KERNEL_NAME=$(basename "$BIN_KERNEL")
    }
}
_get_var

# shellcheck disable=SC2086
_set_rc() {
    [ "$BASH_RC_ROOT" = "$BASH_RC_USER" ] && unset BASH_RC_USER
    case "$1" in
    set)
        [ -n "$(tail -n 1 "$BASH_RC_ROOT")" ] && echo >>"$BASH_RC_ROOT"
        [ -n "$(tail -n 1 "$BASH_RC_USER" >&/dev/null)" ] && echo >>"$BASH_RC_USER"

        echo "source $CLASH_SCRIPT_DIR/common.sh && source $CLASH_SCRIPT_DIR/clashctl.sh" |
            tee -a $BASH_RC_ROOT $BASH_RC_USER >&/dev/null
        ;;
    unset)
        sed -i "\|$CLASH_SCRIPT_DIR|d" $BASH_RC_ROOT $BASH_RC_USER
        ;;
    esac
}

# 默认集成、安装mihomo内核
# 移除/删除mihomo：下载安装clash内核
# shellcheck disable=SC2086
function _get_kernel() {
    [ -f $ZIP_CLASH ] && {
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }

    [ -f $ZIP_MIHOMO ] && {
        ZIP_KERNEL=$ZIP_MIHOMO
        BIN_KERNEL=$BIN_MIHOMO
    }

    [ ! -f $ZIP_MIHOMO ] && [ ! -f $ZIP_CLASH ] && {
        local arch=$(uname -m)
        _failcat "${ZIP_BASE_DIR}：未检测到可用的内核压缩包"
        _download_clash "$arch"
        ZIP_KERNEL=$ZIP_CLASH
        BIN_KERNEL=$BIN_CLASH
    }

    BIN_KERNEL_NAME=$(basename "$BIN_KERNEL")
    _okcat "安装内核：$BIN_KERNEL_NAME"
}

_get_random_port() {
    local randomPort=$((RANDOM % 64512 + 1024))
    ! _is_bind "$randomPort" && { echo "$randomPort" && return; }
    _get_random_port
}

function _get_kernel_port() {
    local mixed_port=$( $BIN_YQ '.mixed-port // ""' $CLASH_CONFIG_RUNTIME)
    local ext_addr=$( $BIN_YQ '.external-controller // ""' $CLASH_CONFIG_RUNTIME)
    local ext_port=${ext_addr##*:}

    MIXED_PORT=${mixed_port:-7890}
    UI_PORT=${ext_port:-9090}

    # 端口占用场景
    local port
    for port in $MIXED_PORT $UI_PORT; do
        _is_already_in_use "$port" "$BIN_KERNEL_NAME" && {
            [ "$port" = "$MIXED_PORT" ] && {
                local newPort=$(_get_random_port)
                local msg="端口占用：${MIXED_PORT} 🎲 随机分配：$newPort"
                 "$BIN_YQ" -i ".mixed-port = $newPort" $CLASH_CONFIG_RUNTIME
                MIXED_PORT=$newPort
                _failcat '🎯' "$msg"
                continue
            }
            [ "$port" = "$UI_PORT" ] && {
                newPort=$(_get_random_port)
                msg="端口占用：${UI_PORT} 🎲 随机分配：$newPort"
                 "$BIN_YQ" -i ".external-controller = \"0.0.0.0:$newPort\"" $CLASH_CONFIG_RUNTIME
                UI_PORT=$newPort
                _failcat '🎯' "$msg"
            }
        }
    done
}

function _get_color() {
    local hex="${1#\#}"
    local r=$((16#${hex:0:2}))
    local g=$((16#${hex:2:2}))
    local b=$((16#${hex:4:2}))
    printf "\e[38;2;%d;%d;%dm" "$r" "$g" "$b"
}
_get_color_msg() {
    local color=$(_get_color "$1")
    local msg=$2
    local reset="\033[0m"
    printf "%b%s%b\n" "$color" "$msg" "$reset"
}

function _okcat() {
    local color=#c8d6e5
    local emoji=😼
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _get_color_msg "$color" "$msg" && return 0
}

function _failcat() {
    local color=#fd79a8
    local emoji=😾
    [ $# -gt 1 ] && emoji=$1 && shift
    local msg="${emoji} $1"
    _get_color_msg "$color" "$msg" >&2 && return 1
}

function _error_quit() {
    [ $# -gt 0 ] && {
        local color=#f92f60
        local emoji=📢
        [ $# -gt 1 ] && emoji=$1 && shift
        local msg="${emoji} $1"
        _get_color_msg "$color" "$msg"
    }
    exec $SHELL
}

_is_bind() {
    local port=$1
    { ss -tulnp || netstat -tulnp; } | grep ":${port}\b"
}

_is_already_in_use() {
    local port=$1
    local progress=$2
    _is_bind "$port" | grep -qs -v "$progress"
}

function _is_root() {
    [ "$(whoami)" = "root" ]
}

# 修改 _valid_env 函数，移除systemd检查
function _valid_env() {
    _is_root || _error_quit "需要 root 或  权限执行"
    [ "$(ps -p $$ -o comm=)" != "bash" ] && _error_quit "当前终端不是 bash"
}

# 添加进程管理函数
_is_running() {
    pgrep -f "$BIN_KERNEL -d $CLASH_BASE_DIR" >/dev/null
}

_start_clash() {
    nohup "$BIN_KERNEL" -d "$CLASH_BASE_DIR" -f "$CLASH_CONFIG_RUNTIME" >"$CLASH_BASE_DIR/clash.log" 2>&1 &
    sleep 1
    _is_running || _error_quit "启动Clash失败"
}

_stop_clash() {
    pkill -f "$BIN_KERNEL -d $CLASH_BASE_DIR" >/dev/null 2>&1
    sleep 0.5
    _is_running && _error_quit "停止Clash失败"
}

_restart_clash() {
    _stop_clash
    _start_clash
}

function _valid_config() {
    [ -e "$1" ] && [ "$(wc -l <"$1")" -gt 1 ] && {
        local test_cmd="$BIN_KERNEL -d $(dirname "$1") -f $1 -t"
        local fail_msg
        fail_msg=$($test_cmd) || {
            $test_cmd
            echo "$fail_msg" | grep -qs "unsupport proxy type" && _error_quit "不支持的代理协议，请安装 mihomo 内核"
        }
    }
}

_download_clash() {
    local arch=$1
    local url sha256sum
    case "$arch" in
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
        _error_quit "未知的架构版本：$arch，请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
        ;;
    esac

    _okcat '⏳' "正在下载：clash：${arch} 架构..."
    local clash_zip="${ZIP_BASE_DIR}/$(basename $url)"
    curl \
        --progress-bar \
        --show-error \
        --fail \
        --insecure \
        --connect-timeout 15 \
        --retry 1 \
        --output "$clash_zip" \
        "$url"
    echo $sha256sum "$clash_zip" | sha256sum -c ||
        _error_quit "下载失败：请自行下载对应版本至 ${ZIP_BASE_DIR} 目录下：https://downloads.clash.wiki/ClashPremium/"
}

function _download_config() {
    _download_raw_config() {
        local dest=$1
        local url=$2
        local agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0'
         curl \
            --silent \
            --show-error \
            --insecure \
            --connect-timeout 4 \
            --retry 1 \
            --user-agent "$agent" \
            --output "$dest" \
            "$url" ||
             wget \
                --no-verbose \
                --no-check-certificate \
                --timeout 3 \
                --tries 1 \
                --user-agent "$agent" \
                --output-document "$dest" \
                "$url"
    }
    _download_convert_config() {
        local dest=$1
        local url=$2
        _start_convert
        local convert_url=$(
            target='clash'
            base_url="http://127.0.0.1:${BIN_SUBCONVERTER_PORT}/sub"
            curl \
                --get \
                --silent \
                --output /dev/null \
                --data-urlencode "target=$target" \
                --data-urlencode "url=$url" \
                --write-out '%{url_effective}' \
                "$base_url"
        )
        _download_raw_config "$dest" "$convert_url"
        _stop_convert
    }
    local dest=$1
    local url=$2
    [ "${url:0:4}" = 'file' ] && return 0
    _download_raw_config "$dest" "$url" || return 1
    _okcat '🍃' '下载成功：内核验证配置...'
    _valid_config "$dest" || {
        _failcat '🍂' "验证失败：尝试订阅转换..."
        _download_convert_config "$dest" "$url" || _failcat '🍂' "转换失败：请检查日志：$BIN_SUBCONVERTER_LOG"
    }
}

_start_convert() {
    _is_already_in_use $BIN_SUBCONVERTER_PORT 'subconverter' && {
        local newPort=$(_get_random_port)
        _failcat '🎯' "端口占用：$BIN_SUBCONVERTER_PORT 🎲 随机分配：$newPort"
        [ ! -e $BIN_SUBCONVERTER_CONFIG ] && {
             /bin/mv -f $BIN_SUBCONVERTER_DIR/pref.example.yml $BIN_SUBCONVERTER_CONFIG
        }
         $BIN_YQ -i ".server.port = $newPort" $BIN_SUBCONVERTER_CONFIG
        BIN_SUBCONVERTER_PORT=$newPort
    }
    local start=$(date +%s)
    # 子shell运行，屏蔽kill时的输出
    ( $BIN_SUBCONVERTER 2>&1 |  tee $BIN_SUBCONVERTER_LOG >/dev/null &)
    while ! _is_bind "$BIN_SUBCONVERTER_PORT" >&/dev/null; do
        sleep 0.05s
        local now=$(date +%s)
        [ $((now - start)) -gt 1 ] && _error_quit "订阅转换服务未启动，请检查日志：$BIN_SUBCONVERTER_LOG"
    done
}
_stop_convert() {
    pkill -9 -f $BIN_SUBCONVERTER >&/dev/null
}

function _merge_config_restart() {
    _stop_clash
    _start_clash
}

function _tunon() {
    _tunstatus 2>/dev/null && return 0
    "$BIN_YQ" -i '.tun.enable = true' "$CLASH_CONFIG_MIXIN"
    _merge_config_restart
    sleep 0.5s
    # 替换journalctl检查为直接检查日志文件
    grep -E -m1 'unsupported kernel version|Start TUN listening error' "$CLASH_BASE_DIR/clash.log" && {
        _tunoff >&/dev/null
        _error_quit '不支持的内核版本'
    }
    _okcat "Tun 模式已开启"
}
