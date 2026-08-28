#!/usr/bin/env bash
# 天枢智投(BestAITrader) 个人自用方案 —— Mac 端业务栈一键关闭脚本。
#
# 与根目录 deploy.py 及 scripts/frp_ecs_mac/setup-frp-mac.sh 对应，关闭本机整套服务：
#   - docker compose 业务栈（默认仅停止容器，保留全部数据）
#   - launchd 管理的 frpc 外网穿透
#
# 用法（在 Mac 项目根目录执行）：
#   bash scripts/frp_ecs_mac/stop-mac.sh
#
# 可选参数：
#   -v|--volumes      连同数据卷一并删除（不可恢复，慎用）
#   --restore-sleep   恢复系统自动睡眠（部署时被 pmset 禁用了）
#   --uninstall       卸载 frpc：删除 launchd 自启项与 ~/.frp 配置/日志

set -euo pipefail

VOLUMES=0
RESTORE_SLEEP=0
UNINSTALL=0
for arg in "$@"; do
    case "$arg" in
        -v|--volumes)    VOLUMES=1 ;;
        --restore-sleep) RESTORE_SLEEP=1 ;;
        --uninstall)     UNINSTALL=1 ;;
        -h|--help)       sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

PLIST_LABEL="com.bestaitrader.frpc"
PLIST_FILE="$HOME/Library/LaunchAgents/$PLIST_LABEL.plist"
CONF_DIR="$HOME/.frp"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log()  { echo -e "\033[32m[mac-stop]\033[0m $*"; }
warn() { echo -e "\033[33m[mac-stop][warn]\033[0m $*"; }

# ---------------------------------------------------------------------------
# 1. 关闭业务栈
# ---------------------------------------------------------------------------
if cd "$ROOT_DIR" && docker compose ps >/dev/null 2>&1; then
    if [[ $VOLUMES -eq 1 ]]; then
        warn "即将删除全部数据卷（数据库、记忆、索引均不可恢复），5 秒内可 Ctrl+C 取消..."
        sleep 5
        docker compose down -v
        log "✓ 业务栈已停止，数据卷已删除。"
    else
        docker compose down
        log "✓ 业务栈已停止（数据保留，可随时 docker compose up -d 恢复）。"
    fi
else
    warn "docker compose 栈未在运行或不可用，跳过。"
fi

# ---------------------------------------------------------------------------
# 2. 关闭 frpc 外网穿透
# ---------------------------------------------------------------------------
if launchctl print "gui/$(id -u)/$PLIST_LABEL" >/dev/null 2>&1; then
    launchctl bootout "gui/$(id -u)/$PLIST_LABEL"
    log "✓ frpc 穿透已停止，外网入口关闭。"
else
    warn "未检测到 frpc 自启任务，跳过。"
fi

if [[ $UNINSTALL -eq 1 ]]; then
    rm -f "$PLIST_FILE"
    rm -rf "$CONF_DIR"
    log "✓ 已删除 frpc 自启项与 $CONF_DIR 配置/日志。"
fi

# ---------------------------------------------------------------------------
# 3. 恢复系统睡眠（可选）
# ---------------------------------------------------------------------------
if [[ $RESTORE_SLEEP -eq 1 ]]; then
    if sudo -n pmset -a sleep 10 2>/dev/null; then
        log "✓ 已恢复系统自动睡眠（10 分钟无操作休眠）。"
    else
        warn "恢复睡眠需要 sudo，请手动执行：sudo pmset -a sleep 10"
    fi
fi

cat <<EOF

============================================================
 Mac 端关闭完成！
   业务栈:   已停止（数据保留在 Docker 卷中）
   frpc:     已停止（外网 http://<ECS公网IP>:18080 失效）
   恢复:     python3 deploy.py 或 docker compose up -d 后
             launchctl bootstrap gui/$(id -u) $PLIST_FILE
   完全释放内存: 退出 Docker Desktop（菜单栏鲸鱼图标 → Quit）
============================================================
EOF
