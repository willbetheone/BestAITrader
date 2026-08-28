#!/usr/bin/env bash
# 天枢智投(BestAITrader) 个人自用方案 —— ECS 端 frps 服务端一键关闭脚本。
#
# 与 scripts/frp_ecs_mac/setup-frp-ecs.sh 对应，用于停止/卸载 ECS 上的 frps 公网入口服务。
#
# 用法（在 ECS 上以 root/sudo 执行）：
#   sudo bash scripts/frp_ecs_mac/stop-frp-ecs.sh
#
# 默认行为：停止 frps 并取消开机自启（保留配置与二进制，可随时重新拉起）。
# 可选参数：
#   --uninstall   彻底卸载：删除 systemd 单元、配置(/etc/frp)与二进制(/opt/frp)

set -euo pipefail

UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=1 ;;
        -h|--help)   sed -n '2,11p' "$0"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

UNIT_FILE="/etc/systemd/system/frps.service"
INSTALL_DIR="/opt/frp"
CONF_DIR="/etc/frp"

log()  { echo -e "\033[32m[frp-ecs-stop]\033[0m $*"; }
warn() { echo -e "\033[33m[frp-ecs-stop][warn]\033[0m $*"; }
die()  { echo -e "\033[31m[frp-ecs-stop][error]\033[0m $*" >&2; exit 1; }

[[ $(id -u) -eq 0 ]] || die "请用 root 或 sudo 运行本脚本。"

# ---------------------------------------------------------------------------
# 1. 停止 frps 并取消开机自启
# ---------------------------------------------------------------------------
if [[ -f "$UNIT_FILE" ]]; then
    log "停止 frps 服务并取消开机自启..."
    systemctl stop frps 2>/dev/null || true
    systemctl disable frps 2>/dev/null || true
    log "✓ frps 已停止，重启后不再自动拉起。"
else
    warn "未检测到 $UNIT_FILE，跳过。"
fi

# ---------------------------------------------------------------------------
# 2. 彻底卸载（仅 --uninstall）
# ---------------------------------------------------------------------------
if [[ $UNINSTALL -eq 1 ]]; then
    rm -f "$UNIT_FILE"
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR" "$CONF_DIR"
    log "✓ 已删除 systemd 单元、配置目录 $CONF_DIR 与二进制目录 $INSTALL_DIR（含 frp.token）。"
fi

# ---------------------------------------------------------------------------
# 3. 结果校验
# ---------------------------------------------------------------------------
sleep 1
if pgrep -x frps >/dev/null 2>&1; then
    warn "仍有 frps 进程残留，请执行 pkill -x frps。"
else
    log "✓ 无 frps 进程残留。"
fi

cat <<EOF

============================================================
 ECS 端关闭完成！
   frps:          已停止（公网入口失效）
   数据保留:      /etc/frp（含 token）与 /opt/frp 均未删除
   重新开启:      sudo systemctl start frps
   （--uninstall 模式则以上均已删除，需重跑 scripts/frp_ecs_mac/setup-frp-ecs.sh）
   安全组提醒:    7000 与公网入口端口建议在阿里云控制台移除放行规则
============================================================
EOF
