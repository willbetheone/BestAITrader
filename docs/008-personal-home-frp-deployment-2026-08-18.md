# 008 - 个人自用部署方案：Mac 跑整套服务 + ECS 内网穿透（无公网 IP 场景）

> 日期：2026-08-18
> 适用场景：家用宽带**无公网 IP**，本地 Mac Pro 2015（16G 内存）跑整套天枢智投服务，
> 现有 2C2G 阿里云 ECS 不升级，仅作为 frp 服务端提供公网访问入口。

---

## 一、方案架构

```
手机/外网浏览器
      │  http://<ECS公网IP>
      ▼
┌─────────────────────────┐
│  阿里云 ECS (2C2G)       │   只跑 frps，不跑业务
│  frps :7000 (控制通道)   │   安全组放行 80、7000
│  公网入口 :80            │
└───────────┬─────────────┘
            │ frp 隧道（frpc 主动外连，无需家里有公网 IP）
            ▼
┌─────────────────────────┐
│  本地 Mac Pro 2015       │
│  frpc (launchd 自启)     │
│  Docker Desktop          │
│  └─ 天枢智投全栈 11 服务  │   nginx 入口 :80
│     http://localhost     │
└─────────────────────────┘
```

**数据流**：外部请求 → ECS:80 → frp 隧道 → Mac:80（nginx）→ backend/sandbox/webfetch/memo/litellm。
LLM API、Tushare 等外部请求全部由 Mac 直接发出，ECS 不承担任何计算，2C2G 完全够用。

---

## 二、前置条件

| 项目 | 要求 |
| --- | --- |
| ECS | 任意 Linux（Ubuntu / Alibaba Cloud Linux 均可），有公网 IP，systemd |
| Mac | Docker Desktop 已安装；建议 Homebrew（无则脚本自动下载二进制） |
| 外部授权 | LLM API Key、Tushare token（部署业务栈时使用） |
| 阿里云控制台 | 能修改 ECS 安全组规则 |

Mac 端 Docker Desktop 资源设置（16G 内存属最低配置）：

- Settings → Resources：内存 **10–12 GB**、CPU **8 线程**、磁盘预留 **≥60 GB**
- General：勾选 **Start Docker Desktop when you sign in**

---

## 三、部署步骤

### 步骤 1：ECS 端安装 frps（约 2 分钟）

把项目同步到 ECS（只需 `scripts/` 目录即可）后执行：

```bash
sudo bash scripts/frp_ecs_mac/setup-frp-ecs.sh
```

脚本自动完成：

1. 按 CPU 架构下载 frp v0.61.1（GitHub 失败自动回退镜像加速）
2. 生成通信令牌（持久化到 `/etc/frp/frp.token`，权限 600）
3. 生成 `/etc/frp/frps.toml` 配置
4. 注册 systemd 服务 `frps.service`，启动并设为开机自启

执行结束会打印 **两个关键信息，务必记下**：

```
FRP_TOKEN:   xxxxxxxxxxxxxxxx   ← Mac 端要用
REMOTE_PORT: 80
```

可选环境变量：`FRP_TOKEN`（自定义令牌）、`FRP_BIND_PORT`（默认 7000）、`REMOTE_PORT`（默认 80，若 80 被占用可改 8080）。

**阿里云控制台操作**：ECS 安全组入方向放行：

| 端口 | 协议 | 授权对象 | 用途 |
| --- | --- | --- | --- |
| 7000 | TCP | 建议只填你家宽带的出口 IP | frps 控制通道 |
| 80 | TCP | 0.0.0.0/0（或按需收紧） | 公网 Web 入口 |

> 家宽出口 IP 会变化，7000 若收紧后连不上，临时改回 0.0.0.0/0 即可（有令牌保护，风险可控）。

### 步骤 2：Mac 端部署业务栈（首次约 10–20 分钟）

在项目根目录执行交互式部署（只需一次）：

```bash
python3 deploy.py
```

按提示输入 LLM API Key、超级用户密码等；脚本会生成 `backend/.env`、`memo/.env`、`litellm/config.yaml` 并启动全部 11 个容器。完成后本机访问 <http://localhost> 验证，登录账号即刚才设置的超级用户。

禁用系统睡眠（防止合盖/空闲断联）：

```bash
sudo pmset -a sleep 0
```

### 步骤 3：Mac 端安装 frpc 穿透（约 2 分钟）

用步骤 1 记下的令牌执行：

```bash
FRP_SERVER_ADDR=<ECS公网IP> FRP_TOKEN=<步骤1输出的令牌> bash scripts/frp_ecs_mac/setup-frp-mac.sh
```

若 ECS 端改过端口，追加 `FRP_SERVER_PORT` / `REMOTE_PORT` 保持一致。

脚本自动完成：

1. 安装 frpc（优先 Homebrew，否则下载官方二进制到 `~/bin/frpc`）
2. 生成配置 `~/.frp/frpc.toml`（权限 600）
3. 注册 launchd 用户代理 `com.bestaitrader.frpc`：**登录后自启 + 崩溃自动重连**
4. 检查本机 80 端口与系统睡眠设置

### 步骤 4：验证

```bash
# 1. 本机访问（应打开登录页）
open http://localhost

# 2. 手机切 4G/5G（脱离家庭 WiFi），浏览器访问
http://<ECS公网IP>
```

两者都能打开登录页即部署成功。

---

## 四、日常使用说明

### 4.1 访问入口

| 场景 | 地址 |
| --- | --- |
| 家里 | http://localhost |
| 外网 | http://<ECS公网IP>（REMOTE_PORT 非 80 时加端口后缀） |

登录使用 `deploy.py` 中设置的超级用户账号；数据源 Key（Tushare / Tavily / NewsAPI）在「系统设置 > 数据源设置」中填写。

### 4.2 常用运维命令

**Mac（业务栈）**：

```bash
docker compose ps                    # 查看 11 个服务状态
docker compose logs -f backend       # 跟踪后端日志
docker compose restart backend       # 重启单个服务
docker compose down && docker compose up -d   # 全栈重启
scripts/database-maintenance.sh backup        # 数据库备份
```

**Mac（穿透）**：

```bash
tail -f ~/.frp/logs/frpc.err.log                                    # 穿透日志
launchctl bootout gui/$(id -u)/com.bestaitrader.frpc               # 停止穿透
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.bestaitrader.frpc.plist  # 启动穿透
```

**ECS（frps）**：

```bash
systemctl status frps                # 服务状态
journalctl -u frps -f                # 查看日志
cat /etc/frp/frp.token               # 查看令牌（忘记时）
systemctl restart frps               # 重启
```

### 4.3 开机自恢复链路

断电/重启后无需人工干预的恢复顺序：

1. ECS：`frps.service` 由 systemd 开机自启 ✓
2. Mac：Docker Desktop 登录自启 → 容器随 compose 策略拉起 ✓
3. Mac：`frpc` 由 launchd 登录后自启、断线自动重连 ✓

> 注意：launchd 用户代理在**用户登录后**才启动。建议 Mac 设置自动登录
> （系统设置 → 用户与群组 → 自动登录），否则重启后需手动登录一次。

---

## 五、故障排查

| 现象 | 排查方法 |
| --- | --- |
| 外网打不开，家里正常 | ① `systemctl status frps` 看 ECS 服务；② 检查安全组 80/7000 是否放行；③ Mac 看 `~/.frp/logs/frpc.err.log` 是否报 `token` 错误（两端令牌不一致） |
| frpc 日志报 `connect to server failed` | ECS 安全组 7000 未放行，或家宽出口 IP 变化后被收紧，放行后自动恢复 |
| frpc 日志报 `remote port already in use` | ECS 上 REMOTE_PORT 被其他进程占用，换端口重跑两端脚本 |
| 页面能打开但很慢 | 受家宽**上行带宽**限制属正常现象；检查是否有其他设备占满上行 |
| 家里 localhost 也打不开 | `docker compose ps` 检查容器；`docker compose logs -f backend` 看报错；16G 内存不足时调低 Docker Desktop 其他占用 |
| Mac 重启后外网不通 | 确认已自动登录且 Docker Desktop 已勾选开机启动；手动执行 4.2 中 launchctl bootstrap |
| ECS 内存吃紧（2C2G） | frps 占用通常 <50MB，若异常可加 1G swap 兜底 |

---

## 六、安全建议（个人自用底线）

1. **令牌保密**：`FRP_TOKEN` 等同入口钥匙，不要提交到 git（两端配置文件均为 600 权限）。
2. **收紧 7000**：安全组中控制通道尽量限定来源 IP。
3. **不要在 ECS 上暴露 LiteLLM 4000 端口**：本方案 4000 只在 Mac 内网，公网仅穿透 80。
4. **账号密码足够长**：超级用户密码 ≥12 位；这是公网可达系统的最后一道防线。
5. 定期执行 `scripts/database-maintenance.sh backup` 并把备份传出 Mac。

---

## 七、方案边界与升级路径

- **本方案定位**：个人自用。Mac 必须常开、自动登录；外网速度受家宽上行限制。
- **何时升级**：需要 7×24 高可用、多人访问、或家宽频繁断电断网时，
  将 ECS 升级到 4C8G，改用 `scripts/deploy-aliyun.sh` 把整套服务迁回 ECS，frp 链路直接废弃。
