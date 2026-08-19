# 009 - Mac 端部署指南（全新 Mac 环境，个人自用方案）

> 日期：2026-08-19
> 适用场景：全新安装的 Mac（Mac Pro 2015 / 16G 内存），从零部署天枢智投业务栈，
> 并通过 frp 穿透到 ECS 公网入口（REMOTE_PORT=18080）。
> 前置：ECS 端已完成 `setup-frp-ecs.sh` 部署、安全组已放行 7000/18080，
> 且已记录 ECS 公网 IP 与 FRP_TOKEN。

---

## 一、安装 Docker Desktop

1. 打开 <https://www.docker.com/products/docker-desktop/> 下载安装包：
   - Apple 芯片（M 系列）→ 选 **Apple Chip**
   - Intel 芯片（如 Mac Pro 2015）→ 选 **Intel Chip**
2. 双击下载的 `.dmg`，将 Docker 图标拖入 Applications
3. 启动 Docker Desktop，按提示完成系统授权
4. 等待菜单栏鲸鱼图标停止动画（引擎就绪），终端验证：
   ```bash
   docker ps
   ```
   不报错即安装成功（个人使用免费，无需登录账号）。

## 二、配置 Docker 资源（关键）

Mac Pro 2015（16G 内存）属最低配置，必须手动调资源，否则容器会被 OOM：

Docker Desktop → **Settings（齿轮图标）→ Resources**：

| 项目 | 设置值 |
| --- | --- |
| Memory（内存） | 10–12 GB |
| CPU | 8 线程（拉满） |
| Disk image size（磁盘） | ≥60 GB |

点 **Apply & Restart**。另外在 **General** 页勾选 **Start Docker Desktop when you sign in**（开机自启）。

## 三、确认 Python 环境

```bash
python3 --version
```

- 能输出版本号（3.8+）即可；
- 若弹出「安装命令行开发者工具」提示，点击**安装**并等待完成（约几分钟）。

## 四、部署业务栈（首次约 10–20 分钟）

```bash
cd /Users/zhangdong/workspace/量化/code/BestAITrader
python3 deploy.py
```

交互式输入项（按顺序）：

| 提示项 | 填写内容 |
| --- | --- |
| LLM API Base | `https://dashscope.aliyuncs.com/compatible-mode/v1`（阿里百炼） |
| LLM API Key | 百炼控制台创建的 `sk-xxx` |
| 模型 | `qwen-plus`（推荐）或 `qwen-turbo` |
| 初始超级用户密码 | ≥12 位，**务必记牢**（登录用） |

脚本自动完成：校验 LLM Key → 生成 `backend/.env`、`memo/.env`、`litellm/config.yaml`
→ 拉取镜像 → 启动全部 11 个容器 → 健康检查。

完成后浏览器打开 <http://localhost>，能看到登录页即部署成功。

**部署后立即填写数据源**：用超级用户登录 → 「系统设置 > 数据源设置」→
填写 Tushare token（tushare.pro 注册免费获取）；Tavily/NewsAPI 可选。

## 五、建立 frp 穿透（外网访问入口）

用 ECS 端 `setup-frp-ecs.sh` 输出的令牌执行：

```bash
FRP_SERVER_ADDR=<ECS公网IP> FRP_TOKEN=<令牌> REMOTE_PORT=18080 \
    bash scripts/setup-frp-mac.sh
```

脚本自动完成：安装 frpc（Homebrew 优先，无则下载官方二进制）
→ 生成 `~/.frp/frpc.toml` → 注册 launchd 登录自启 + 崩溃自动重连。

防止系统睡眠导致穿透中断：

```bash
sudo pmset -a sleep 0
```

> 建议同时在「系统设置 → 用户与群组」开启**自动登录**：
> launchd 用户代理在登录后才启动，重启后无需人工干预。

## 六、验证

1. **本机**：`open http://localhost` 打开登录页 ✓
2. **外网**：手机切 4G/5G（脱离家庭 WiFi），浏览器访问
   `http://<ECS公网IP>:18080`，能打开登录页即全链路成功 ✓

## 七、日常运维命令

```bash
docker compose ps                     # 查看 11 个服务状态
docker compose logs -f backend        # 跟踪后端日志
docker compose restart backend        # 重启单个服务
docker compose down && docker compose up -d   # 全栈重启
scripts/database-maintenance.sh backup        # 数据库备份

tail -f ~/.frp/logs/frpc.err.log      # 穿透日志
launchctl bootout gui/$(id -u)/com.bestaitrader.frpc      # 停止穿透
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.bestaitrader.frpc.plist  # 启动穿透
```

## 八、常见问题

| 现象 | 处理 |
| --- | --- |
| `docker ps` 报 Cannot connect | Docker Desktop 未启动或未授权，启动并等待鲸鱼图标稳定 |
| deploy.py 校验 LLM 失败 | 检查百炼 Key 是否复制完整、模型名拼写（qwen-plus）、账号是否有余额/免费额度 |
| 镜像拉取很慢 | 正常现象，首次需拉取约 10GB；可在 Docker Desktop → Docker Engine 里配置国内镜像加速 |
| 容器反复重启 | 内存不足，检查 Docker Desktop 内存是否已调到 10–12GB |
| 外网打不开、家里正常 | 看 `~/.frp/logs/frpc.err.log`：token 错误 → 两端令牌不一致；connect failed → ECS 安全组 7000 未放行 |
| Mac 重启后外网不通 | 确认已自动登录、Docker Desktop 已勾选开机自启，手动执行上面 launchctl bootstrap |
| 页面响应慢 | 受家宽上行带宽限制属正常，个人自用可接受 |

## 九、开机自恢复链路（无需人工干预）

1. Mac 开机自动登录 → Docker Desktop 自启 → 容器随 compose 策略拉起
2. launchd 自动启动 frpc → 与 ECS frps 建立隧道（断线自动重连）
3. 外网 `http://<ECS公网IP>:18080` 恢复访问
