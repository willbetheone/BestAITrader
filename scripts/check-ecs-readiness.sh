#!/usr/bin/env bash
# 天枢智投(BestAITrader) 个人自用方案 —— ECS 就绪检测脚本（只读检查，不改动任何配置）。
#
# 用法（在 ECS 上执行，root 或普通用户均可）：
#   bash scripts/check-ecs-readiness.sh
#
# 检测项：systemd / CPU 架构 / 80 与 7000 端口占用 / 外网连通性 / 内存与磁盘参考。
# 全部 PASS 即可执行 sudo bash scripts/setup-frp-ecs.sh。

set -uo pipefail

PASS=0
FAIL=0
WARN=0

FRP_BIND_PORT="${FRP_BIND_PORT:-7000}"
REMOTE_PORT="${REMOTE_PORT:-80}"

ok()   { echo -e "  \033[32m[PASS]\033[0m $*"; PASS=$((PASS+1)); }
bad()  { echo -e "  \033[31m[FAIL]\033[0m $*"; FAIL=$((FAIL+1)); }
note() { echo -e "  \033[33m[WARN]\033[0m $*"; WARN=$((WARN+1)); }
info() { echo -e "  [info] $*"; }

echo "============================================================"
echo " ECS 就绪检测（frp 公网入口方案）"
echo "============================================================"

# 1. root 权限（非必需，但缺失时提示）
echo ""
echo "1) 权限检查"
if [[ $(id -u) -eq 0 ]]; then
    ok "当前为 root 用户，可直接执行部署脚本。"
else
    if sudo -n true 2>/dev/null; then
        ok "当前用户具备免密 sudo。"
    else
        note "当前非 root 且 sudo 需要密码，部署时请用 sudo bash scripts/setup-frp-ecs.sh 并输入密码。"
    fi
fi

# 2. 操作系统与 systemd
echo ""
echo "2) 操作系统与 systemd"
if [[ "$(uname -s)" == "Linux" ]]; then
    ok "操作系统为 Linux：$(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -r)"
else
    bad "非 Linux 系统：$(uname -s)"
fi
if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
    ok "systemd 正常运行（frps 服务注册依赖它）。"
else
    bad "systemd 不可用，setup-frp-ecs.sh 无法注册 frps 服务。"
fi

# 3. CPU 架构
echo ""
echo "3) CPU 架构"
case "$(uname -m)" in
    x86_64|amd64)  ok "架构 $(uname -m)（frp linux_amd64 可用）。" ;;
    aarch64|arm64) ok "架构 $(uname -m)（frp linux_arm64 可用）。" ;;
    *) bad "不支持的架构 $(uname -m)，无官方 frp 二进制。" ;;
esac

# 4. 端口占用
echo ""
echo "4) 端口占用检查"
port_free() {
    local port="$1"
    if command -v ss >/dev/null 2>&1; then
        ! ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
    elif command -v netstat >/dev/null 2>&1; then
        ! netstat -ltn 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}\$"
    else
        return 2
    fi
}
for p in "$REMOTE_PORT" "$FRP_BIND_PORT"; do
    if port_free "$p"; then
        ok "端口 $p 空闲。"
    else
        status=$?
        if [[ $status -eq 2 ]]; then
            note "ss/netstat 均缺失，无法检测端口 $p，请手动确认未被占用。"
        else
            bad "端口 $p 已被占用，请释放或改用其他端口（REMOTE_PORT=xxx 重跑）。"
            ss -ltnp 2>/dev/null | grep -E "[:.]${p}\$" | sed 's/^/         /' || true
        fi
    fi
done

# 5. 外网连通性
echo ""
echo "5) 外网连通性（frp 下载与隧道连通依赖）"
if curl -fsS -m 8 -o /dev/null https://mirrors.aliyun.com/; then
    ok "阿里云镜像源可达（备用下载通道正常）。"
else
    bad "无法访问 mirrors.aliyun.com，请检查 ECS 公网带宽是否 >0。"
fi
if curl -fsS -m 8 -o /dev/null https://github.com/; then
    ok "github.com 可达（frp 官方下载通道正常）。"
else
    note "github.com 不可达，部署脚本将自动走镜像加速下载，无需处理。"
fi

# 6. 依赖命令
echo ""
echo "6) 依赖命令"
for cmd in curl tar systemctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd 已安装。"
    else
        bad "$cmd 缺失，请先安装（如 yum install -y curl tar）。"
    fi
done

# 7. 资源参考（frps 很轻量，仅提示）
echo ""
echo "7) 资源状况（仅参考，frps 占用 <50MB）"
if command -v free >/dev/null 2>&1; then
    info "内存：$(free -h | awk '/^Mem:/{print $2" 总量 / "$3" 已用 / "$7" 可用"}')"
fi
info "磁盘：$(df -h / | awk 'NR==2{print $2" 总量 / "$3" 已用 / "$4" 可用"}')"

# 8. 安全组提醒（ECS 内部无法自检）
echo ""
echo "8) 安全组（无法从 ECS 内部自检，请在阿里云控制台确认）"
note "请确认安全组入方向已放行 TCP ${FRP_BIND_PORT} 与 TCP ${REMOTE_PORT}。"

# 汇总
echo ""
echo "============================================================"
if [[ $FAIL -eq 0 ]]; then
    echo -e " \033[32m检测通过：PASS=$PASS FAIL=$FAIL WARN=$WARN\033[0m"
    echo " 下一步：sudo bash scripts/setup-frp-ecs.sh"
    exit 0
else
    echo -e " \033[31m检测未通过：PASS=$PASS FAIL=$FAIL WARN=$WARN，请先解决上方 FAIL 项。\033[0m"
    exit 1
fi
