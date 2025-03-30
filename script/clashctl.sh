#!/bin/bash
# shellcheck disable=SC2155

# 修改 clashon 函数
function clashon() {
    _get_kernel_port
    _start_clash && _okcat '已开启代理环境' ||
        _failcat '启动失败: 执行 "clashstatus" 查看日志' || return 1
    
    local http_proxy_addr="http://127.0.0.1:${MIXED_PORT}"
    local socks_proxy_addr="socks5://127.0.0.1:${MIXED_PORT}"
    local no_proxy_addr="localhost,127.0.0.1,::1"
    
    export http_proxy=$http_proxy_addr
    export https_proxy=$http_proxy
    export HTTP_PROXY=$http_proxy
    export HTTPS_PROXY=$http_proxy
    
    export all_proxy=$socks_proxy_addr
    export ALL_PROXY=$all_proxy
    
    export no_proxy=$no_proxy_addr
    export NO_PROXY=$no_proxy
}

systemctl is-active "$BIN_KERNEL_NAME" >&/dev/null && [ -z "$http_proxy" ] && {
    _is_root || _failcat '当前 shell 未检测到代理变量，需执行 clashon 开启代理环境' && clashon
}

# 修改 clashoff 函数
function clashoff() {
    _stop_clash && _okcat '已关闭代理环境' ||
        _failcat '关闭失败: 执行 "clashstatus" 查看日志' || return 1
    
    unset http_proxy
    unset https_proxy
    unset HTTP_PROXY
    unset HTTPS_PROXY
    unset all_proxy
    unset ALL_PROXY
    unset no_proxy
    unset NO_PROXY
}

clashrestart() {
    { clashoff && clashon; } >&/dev/null
}

# 修改 clashstatus 函数
clashstatus() {
    if _is_running; then
        _okcat "Clash 正在运行"
        tail -n 10 "$CLASH_BASE_DIR/clash.log" 2>/dev/null
    else
        _failcat "Clash 未运行"
    fi
}

# 修改 _tunon 函数中的日志检查
_tunon() {
    _tunstatus 2>/dev/null && return 0
     "$BIN_YQ" -i '.tun.enable = true' "$CLASH_CONFIG_MIXIN"
    _merge_config_restart
    sleep 0.5s
    grep -E -m1 'unsupported kernel version|Start TUN listening error' "$CLASH_BASE_DIR/clash.log" && {
        _tunoff >&/dev/null
        _error_quit '不支持的内核版本'
    }
    _okcat "Tun 模式已开启"
}

function clashtun() {
    case "$1" in
    on)
        _tunon
        ;;
    off)
        _tunoff
        ;;
    *)
        _tunstatus
        ;;
    esac
}

function clashupdate() {
    local url=$(cat "$CLASH_CONFIG_URL")
    local is_auto

    case "$1" in
    auto)
        is_auto=true
        [ -n "$2" ] && url=$2
        ;;
    log)
         tail "${CLASH_UPDATE_LOG}" 2>/dev/null || _failcat "暂无更新日志"
        return 0
        ;;
    *)
        [ -n "$1" ] && url=$1
        ;;
    esac

    # 如果没有提供有效的订阅链接（url为空或者不是http开头），则使用默认配置文件
    [ "${url:0:4}" != "http" ] && {
        _failcat "没有提供有效的订阅链接：使用 ${CLASH_CONFIG_RAW} 进行更新..."
        url="file://$CLASH_CONFIG_RAW"
    }

    # 如果是自动更新模式，则设置定时任务
    [ "$is_auto" = true ] && {
         grep -qs 'clashupdate' "$CLASH_CRON_TAB" || echo "0 0 */2 * * . $BASH_RC_ROOT;clashupdate $url" |  tee -a "$CLASH_CRON_TAB" >&/dev/null
        _okcat "定时任务设置成功" && return 0
    }

    _okcat '👌' "备份配置：$CLASH_CONFIG_RAW_BAK"
     cat "$CLASH_CONFIG_RAW" |  tee "$CLASH_CONFIG_RAW_BAK" >&/dev/null

    _rollback() {
        _failcat '🍂' "$1"
         cat "$CLASH_CONFIG_RAW_BAK" |  tee "$CLASH_CONFIG_RAW" >&/dev/null
        _failcat '❌' "[$(date +"%Y-%m-%d %H:%M:%S")] 订阅更新失败：$url" 2>&1 |  tee -a "${CLASH_UPDATE_LOG}" >&/dev/null
        _error_quit
    }

    _download_config "$CLASH_CONFIG_RAW" "$url" || _rollback "更新失败：已回滚配置"
    _valid_config "$CLASH_CONFIG_RAW" || _rollback "转换失败：已回滚配置，请检查日志：$BIN_SUBCONVERTER_LOG"

    _merge_config_restart && _okcat '🍃' '订阅更新成功'
    echo "$url" |  tee "$CLASH_CONFIG_URL" >&/dev/null
    _okcat '✅' "[$(date +"%Y-%m-%d %H:%M:%S")] 订阅更新成功：$url" |  tee -a "${CLASH_UPDATE_LOG}" >&/dev/null
}

function clashmixin() {
    case "$1" in
    -e)
         vim "$CLASH_CONFIG_MIXIN" && {
            _merge_config_restart && _okcat "配置更新成功，已重启生效"
        }
        ;;
    -r)
        less "$CLASH_CONFIG_RUNTIME"
        ;;
    *)
        less "$CLASH_CONFIG_MIXIN"
        ;;
    esac
}

function clash() {
    local color=#c8d6e5
    local prefix=$(_get_color "$color")
    local suffix=$(printf '\033[0m')
    printf "%b\n" "$(
        cat <<EOF | column -t -s ',' | sed -E "/clash/ s|(clash)(\w*)|\1${prefix}\2${suffix}|g"
Usage:
    clash                    命令一览,
    clashon                  开启代理,
    clashoff                 关闭代理,
    clashui                  面板地址,
    clashstatus              内核状况,
    clashtun     [on|off]    Tun 模式,
    clashmixin   [-e|-r]     Mixin 配置,
    clashsecret  [secret]    Web 密钥,
    clashupdate  [auto|log]  更新订阅,
EOF
    )"
}
