#!/bin/bash
# shellcheck disable=SC1091
. script/common.sh >&/dev/null
. script/clashctl.sh >&/dev/null

_valid_env

clashoff >&/dev/null

# 移除开机启动脚本（如果存在）
rm -f /etc/rc.local

rm -rf "$CLASH_BASE_DIR"
_set_rc unset
_okcat '✨' '已卸载，相关配置已清除'
exec bash
