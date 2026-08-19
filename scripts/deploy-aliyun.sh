#!/usr/bin/env bash
# 天枢智投(BestAITrader) 阿里云服务器一键自动化部署脚本。
#
# 与根目录 deploy.py 的区别：本脚本完全非交互，配置从 deploy.conf 或环境变量读取，
# 适合远程服务器上自动化部署。会自动安装 Docker（使用阿里云镜像源）。
#
# 用法：
#   1. cp scripts/deploy.conf.example deploy.conf && vi deploy.conf
#   2. bash scripts/deploy-aliyun.sh
#
# 常用参数：
#   --overwrite        覆盖已存在的 backend/.env / memo/.env / litellm/config.yaml
#   --no-start         只生成配置，不启动容器
#   --no-health-check  启动后跳过健康检查
#   --skip-docker-install 跳过 Docker 安装检测（已确认环境可用时）

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BACKEND_ENV="backend/.env"
MEMO_ENV="memo/.env"
LITELLM_CONFIG="litellm/config.yaml"
COMPOSE_FILE="docker-compose.yml"

# ---------------------------------------------------------------------------
# 参数解析
# ---------------------------------------------------------------------------
OVERWRITE=0
NO_START=0
NO_HEALTH_CHECK=0
SKIP_DOCKER_INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --overwrite)           OVERWRITE=1 ;;
        --no-start)            NO_START=1 ;;
        --no-health-check)     NO_HEALTH_CHECK=1 ;;
        --skip-docker-install) SKIP_DOCKER_INSTALL=1 ;;
        -h|--help)             sed -n '2,16p' "$0"; exit 0 ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

log()  { echo -e "\033[32m[deploy]\033[0m $*"; }
warn() { echo -e "\033[33m[deploy][warn]\033[0m $*"; }
die()  { echo -e "\033[31m[deploy][error]\033[0m $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1. 加载配置：deploy.conf > 环境变量 > 默认值
# ---------------------------------------------------------------------------
if [[ -f "$ROOT_DIR/deploy.conf" ]]; then
    log "加载配置文件 deploy.conf"
    # shellcheck disable=SC1091
    source "$ROOT_DIR/deploy.conf"
fi

SUPERUSER="${SUPERUSER:-tradeuser}"
SUPERUSER_EMAIL="${SUPERUSER_EMAIL:-tradeuser@example.com}"
SUPERUSER_PASSWORD="${SUPERUSER_PASSWORD:-}"

LLM_API_BASE="${LLM_API_BASE:-https://api.deepseek.com}"
LLM_API_KEY="${LLM_API_KEY:-}"
LLM_VALIDATION_MODEL="${LLM_VALIDATION_MODEL:-deepseek-v4-flash}"
LLM_LITELLM_MODEL="${LLM_LITELLM_MODEL:-deepseek/deepseek-v4-flash}"

# 可选第二组 LLM：LLM2_API_BASE / LLM2_API_KEY / LLM2_VALIDATION_MODEL / LLM2_LITELLM_MODEL
# 可选：阿里云容器镜像加速器地址（控制台 > 容器镜像服务 > 镜像工具 > 镜像加速器）
DOCKER_REGISTRY_MIRROR="${DOCKER_REGISTRY_MIRROR:-}"

[[ -n "$SUPERUSER_PASSWORD" ]] || die "缺少 SUPERUSER_PASSWORD（至少 12 位），请在 deploy.conf 或环境变量中配置。"
[[ ${#SUPERUSER_PASSWORD} -ge 12 ]] || die "SUPERUSER_PASSWORD 至少 12 位。"
[[ -n "$LLM_API_KEY" ]] || die "缺少 LLM_API_KEY，请在 deploy.conf 或环境变量中配置。"

if [[ -f "$BACKEND_ENV" || -f "$MEMO_ENV" || -f "$LITELLM_CONFIG" ]] && [[ $OVERWRITE -eq 0 ]]; then
    die "检测到已有配置文件（backend/.env / memo/.env / litellm/config.yaml）。确认覆盖请加 --overwrite。"
fi

# ---------------------------------------------------------------------------
# 2. 安装 Docker（若缺失），优先使用阿里云镜像源
# ---------------------------------------------------------------------------
ensure_docker() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        log "Docker 与 Compose v2 已就绪：$(docker compose version --short 2>/dev/null || docker compose version)"
        return
    fi
    if [[ $SKIP_DOCKER_INSTALL -eq 1 ]]; then
        die "Docker 或 Compose v2 不可用，且指定了 --skip-docker-install。"
    fi
    [[ $(id -u) -eq 0 ]] || die "自动安装 Docker 需要 root 权限，请用 root 或 sudo 运行。"
    log "开始安装 Docker Engine + Compose 插件（阿里云镜像源）..."

    if command -v apt-get >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
            | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
            > /etc/apt/sources.list.d/docker.list
        apt-get update -y
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
        # 适配 Alibaba Cloud Linux / CentOS / RHEL
        PKG_MGR="yum"; command -v dnf >/dev/null 2>&1 && PKG_MGR="dnf"
        $PKG_MGR install -y yum-utils
        yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
        $PKG_MGR install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    else
        die "无法识别的发行版包管理器，请手动安装 Docker Engine 与 docker-compose-plugin 后重试。"
    fi

    systemctl enable --now docker
    log "Docker 安装完成。"
}

setup_registry_mirror() {
    [[ -n "$DOCKER_REGISTRY_MIRROR" ]] || return 0
    log "配置容器镜像加速器：$DOCKER_REGISTRY_MIRROR"
    mkdir -p /etc/docker
    if [[ -f /etc/docker/daemon.json ]]; then
        cp /etc/docker/daemon.json "/etc/docker/daemon.json.bak.$(date +%s)"
    fi
    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ["$DOCKER_REGISTRY_MIRROR"]
}
EOF
    systemctl restart docker
}

# ---------------------------------------------------------------------------
# 3. 校验 LLM Key（OpenAI-compatible chat/completions 直连）
# ---------------------------------------------------------------------------
validate_llm() {
    local api_base="$1" api_key="$2" model="$3"
    local url="${api_base%/}"
    [[ "$url" == */chat/completions ]] || url="$url/chat/completions"
    log "校验 LLM：$url (model=$model)"
    local response http_code
    response=$(curl -sS -m 30 -w '\n%{http_code}' "$url" \
        -H "Authorization: Bearer $api_key" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}],\"max_tokens\":8,\"temperature\":0}") || die "LLM 校验请求失败：网络不可达 $url"
    http_code=$(echo "$response" | tail -n1)
    if [[ "$http_code" != "200" ]]; then
        echo "$response" | head -n -1
        die "LLM 校验失败（HTTP $http_code），请检查 LLM_API_BASE / LLM_API_KEY / LLM_VALIDATION_MODEL。"
    fi
    if ! echo "$response" | grep -q '"choices"'; then
        die "LLM 响应缺少 choices 字段：$(echo "$response" | head -n -1)"
    fi
    log "LLM 校验通过。"
}

# ---------------------------------------------------------------------------
# 4. 生成配置文件
# ---------------------------------------------------------------------------
rand_token() { # $1=长度
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 "$1" | tr '+/' '-_' | tr -d '=\n'
    else
        head -c "$1" /dev/urandom | base64 | tr '+/' '-_' | tr -d '=\n'
    fi
}

SECRET_KEY="${SECRET_KEY:-$(rand_token 48)}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-$(rand_token 32)}"

render_litellm_endpoint() { # $1=index $2=litellm_model $3=api_key $4=api_base
    local idx="$1" model="$2" key="$3" base="$4" anchor="shared_litellm_params$1"
    cat <<EOF
  - model_name: gpt-4o-mini
    litellm_params:
      <<: &$anchor
        model: "$model"
        api_key: "$key"
        api_base: "$base"
      temperature: 0.2

  - model_name: openai-compatible
    litellm_params:
      <<: *$anchor
      temperature: 0.2
      extra_body:
        thinking:
          type: disabled

  - model_name: openai-compatible-thinking
    litellm_params:
      <<: *$anchor
      extra_body:
        thinking:
          type: enabled
EOF
}

write_configs() {
    validate_llm "$LLM_API_BASE" "$LLM_API_KEY" "$LLM_VALIDATION_MODEL"
    if [[ -n "${LLM2_API_KEY:-}" ]]; then
        validate_llm "${LLM2_API_BASE:-$LLM_API_BASE}" "$LLM2_API_KEY" "${LLM2_VALIDATION_MODEL:-$LLM_VALIDATION_MODEL}"
    fi

    log "生成 $BACKEND_ENV"
    mkdir -p backend memo litellm
    cat > "$BACKEND_ENV" <<EOF
# Generated by scripts/deploy-aliyun.sh. Do not commit this file.
FIRST_SUPERUSER="$SUPERUSER"
FIRST_SUPERUSER_EMAIL="$SUPERUSER_EMAIL"
FIRST_SUPERUSER_PASSWORD="$SUPERUSER_PASSWORD"
SECRET_KEY="$SECRET_KEY"

LLM_API_KEY="$LITELLM_MASTER_KEY"
ENABLE_OPENAPI_DOCS=false
EOF

    log "生成 $MEMO_ENV"
    cat > "$MEMO_ENV" <<EOF
# Generated by scripts/deploy-aliyun.sh. Do not commit this file.
MEMOFLUX_LLM_BASE_URL=http://litellm:4000/v1
MEMOFLUX_LLM_API_KEY=$LITELLM_MASTER_KEY
MEMOFLUX_LLM_MODEL=openai-compatible
EOF

    log "生成 $LITELLM_CONFIG"
    {
        echo "# Generated by scripts/deploy-aliyun.sh. Do not commit this file."
        echo "model_list:"
        render_litellm_endpoint 0 "$LLM_LITELLM_MODEL" "$LLM_API_KEY" "$LLM_API_BASE"
        if [[ -n "${LLM2_API_KEY:-}" ]]; then
            render_litellm_endpoint 1 "${LLM2_LITELLM_MODEL:-$LLM_LITELLM_MODEL}" "$LLM2_API_KEY" "${LLM2_API_BASE:-$LLM_API_BASE}"
        fi
        cat <<EOF

general_settings:
  master_key: "$LITELLM_MASTER_KEY"
  database_url: postgresql://tradeuser:tradepassword@postgres:5432/litellm
EOF
    } > "$LITELLM_CONFIG"

    chmod 600 "$BACKEND_ENV" "$MEMO_ENV" "$LITELLM_CONFIG"
    log "配置已生成：backend/.env, memo/.env, litellm/config.yaml"
}

# ---------------------------------------------------------------------------
# 5. 启动 Compose 栈
# ---------------------------------------------------------------------------
start_stack() {
    [[ -f "$COMPOSE_FILE" ]] || die "未找到 $COMPOSE_FILE，请确认在项目根目录且已拉取全部子模块（git submodule update --init --recursive）。"
    if [[ ! -f "nginx.conf" ]]; then
        warn "未找到 nginx.conf，将使用仓库内默认配置失败时请检查 git 仓库完整性。"
    fi
    log "拉取镜像（首次可能较慢，ghcr.io 拉取失败时可配置代理或手动同步镜像）..."
    docker compose pull
    docker compose up -d
    docker compose ps
}

# ---------------------------------------------------------------------------
# 6. 健康检查
# ---------------------------------------------------------------------------
health_check() {
    log "等待服务健康检查通过（最多 5 分钟）..."
    local services=(backend sandbox webfetch memo)
    local deadline=$(( $(date +%s) + 300 ))
    while (( $(date +%s) < deadline )); do
        local all_ok=1
        for svc in "${services[@]}"; do
            local status
            status=$(docker inspect --format '{{.State.Health.Status}}' "bat.$svc" 2>/dev/null || echo "missing")
            if [[ "$status" != "healthy" ]]; then
                all_ok=0
                break
            fi
        done
        if [[ $all_ok -eq 1 ]] && curl -fsS -m 5 http://127.0.0.1/ >/dev/null 2>&1; then
            break
        fi
        sleep 10
    done

    local failed=0
    for svc in "${services[@]}"; do
        local container="bat.$svc"
        local status
        status=$(docker inspect --format '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
        if [[ "$status" == "healthy" ]]; then
            log "✓ $svc healthy"
        else
            warn "✗ $svc 状态: $status（可执行 docker compose logs -f $svc 查看）"
            failed=1
        fi
    done

    if curl -fsS -m 10 http://127.0.0.1:4000/health/liveliness >/dev/null 2>&1; then
        log "✓ LiteLLM 网关 healthy"
    else
        warn "✗ LiteLLM 网关暂未就绪，可稍后重试或查看 docker compose logs -f litellm"
        failed=1
    fi

    if [[ $failed -eq 0 ]]; then
        log "全部服务健康检查通过。"
    fi
}

# ---------------------------------------------------------------------------
# 主流程
# ---------------------------------------------------------------------------
if [[ $NO_START -eq 0 ]]; then
    ensure_docker
    if [[ -n "$DOCKER_REGISTRY_MIRROR" ]]; then
        if [[ $(id -u) -eq 0 ]]; then
            setup_registry_mirror
        else
            warn "配置镜像加速器需要 root 权限，已跳过。"
        fi
    fi
fi

write_configs

if [[ $NO_START -eq 1 ]]; then
    log "已按 --no-start 生成配置，未启动容器。"
    exit 0
fi

start_stack

if [[ $NO_HEALTH_CHECK -eq 0 ]]; then
    health_check
fi

PUBLIC_IP=$(curl -fsS -m 5 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null \
    || curl -fsS -m 5 ifconfig.me 2>/dev/null || echo "<服务器IP>")

cat <<EOF

============================================================
 部署完成！
   主系统:          http://$PUBLIC_IP
   LiteLLM 管理 UI: http://$PUBLIC_IP:4000/ui

 后续步骤：
   1. 阿里云控制台安全组放行 80、4000 端口（按需收紧来源 IP）。
   2. 登录后进入 系统设置 > 数据源设置，填写 Tushare / Tavily / NewsAPI Key。
   3. 生产环境请按 SECURITY.md 收紧暴露面（建议关闭 4000 公网访问）。

 常用命令：
   docker compose ps
   docker compose logs -f backend
   scripts/database-maintenance.sh backup
============================================================
EOF
