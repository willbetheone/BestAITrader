#!/usr/bin/env bash
# 天枢智投(BestAITrader) Mac 本地一键关闭脚本。
#
# 与 scripts/frp_ecs_mac/stop-mac.sh 的区别：本脚本只关闭本机 Docker Compose
# 业务栈，不涉及 frpc 外网穿透（穿透请单独用 stop-mac.sh 或 launchctl 停止）。
#
# 用法（在 Mac 项目根目录执行）：
#   bash scripts/deploy_mac_local/stop.sh
#
# 可选参数：
#   -v|--volumes   连同数据卷一并删除（不可恢复，慎用）
#   --quit-docker  关闭后退出 Docker Desktop（释放内存）

set -euo pipefail

VOLUMES=0
QUIT_DOCKER=0
for arg in "$@"; do
    case "$arg" in
        -v|--volumes)   VOLUMES=1 ;;
        --quit-docker)  QUIT_DOCKER=1 ;;
        -h|--help)      sed -n '2,12p' "$0"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

log()  { echo -e "\033[32m[mac-stop]\033[0m $*"; }
warn() { echo -e "\033[33m[mac-stop][warn]\033[0m $*"; }

# ---------------------------------------------------------------------------
# 1. 关闭业务栈（默认保留全部数据）
# ---------------------------------------------------------------------------
if cd "$ROOT_DIR" && docker compose ps >/dev/null 2>&1; then
    if [[ $VOLUMES -eq 1 ]]; then
        warn "即将删除全部数据卷（数据库、记忆、索引均不可恢复），5 秒内可 Ctrl+C 取消..."
        sleep 5
        docker compose down -v
        log "✓ 业务栈已停止，数据卷已删除。"
    else
        docker compose down
        log "✓ 业务栈已停止（数据保留，可随时 bash scripts/deploy_mac_local/deploy.sh 恢复）。"
    fi
else
    warn "docker compose 栈未在运行或不可用，跳过。"
fi

# ---------------------------------------------------------------------------
# 2. 退出 Docker Desktop（可选，释放内存）
# ---------------------------------------------------------------------------
if [[ $QUIT_DOCKER -eq 1 ]]; then
    if osascript -e 'quit app "Docker"' >/dev/null 2>&1; then
        log "✓ 已请求退出 Docker Desktop。"
    else
        warn "退出 Docker Desktop 失败，请手动点击菜单栏鲸鱼图标 → Quit。"
    fi
fi

cat <<EOF

============================================================
 Mac 本地关闭完成！
   业务栈:  已停止（数据保留在 Docker 卷中）
   恢复:    bash scripts/deploy_mac_local/deploy.sh
   穿透:    frpc 仍可能运行，可用 scripts/frp_ecs_mac/stop-mac.sh 一并关闭
============================================================
EOF
