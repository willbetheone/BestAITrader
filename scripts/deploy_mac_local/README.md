# 天枢智投（BestAITrader）Mac 本地部署使用说明

> 适用场景：个人 Mac 本机部署整套天枢智投业务栈（入口 `http://localhost`），
> 日常启动/关闭通过 `scripts/deploy_mac_local/` 下的脚本完成。
> 若需外网访问，请配合 `scripts/frp_ecs_mac/` 下的 frp 脚本使用。

## 一、脚本说明

| 脚本 | 用途 |
| --- | --- |
| `deploy.sh` | 一键部署/启动：生成配置 → 校验 LLM → 拉起 Docker Desktop → 启动容器 → 健康检查 |
| `stop.sh` | 一键关闭：停止容器（默认保留数据），可选删数据卷/退出 Docker Desktop |

与根目录 `deploy.py` 的区别：`deploy.py` 为交互式（逐项提问），本脚本为非交互式，
配置统一从根目录 `deploy.conf` 读取，适合重复部署与自动化。

## 二、前置要求

- macOS（Apple 芯片或 Intel 均可）
- 已安装 Docker Desktop（首次启动会自动拉起）
- 推荐配置：16GB 内存 / 8 核 CPU / 磁盘剩余 ≥30GB
- Docker Desktop 建议分配：内存 10–12GB、CPU 8 线程、磁盘上限 ≥60GB

## 三、首次部署

1. 复制配置模板并填写：

   ```bash
   cp scripts/deploy.conf.example deploy.conf && vi deploy.conf
   ```

   必填项：
   - `SUPERUSER_PASSWORD`：初始超级用户密码，至少 12 位（登录系统用，务必记牢）
   - `LLM_API_KEY`：OpenAI 兼容接口的 API Key
   - 可选调整：`LLM_API_BASE`（默认 DeepSeek）、`LLM_VALIDATION_MODEL`、`LLM_LITELLM_MODEL`

2. 执行部署（首次约 10–20 分钟，含镜像拉取）：

   ```bash
   bash scripts/deploy_mac_local/deploy.sh
   ```

   常用参数：
   - `--overwrite`：覆盖已存在的 `backend/.env` / `memo/.env` / `litellm/config.yaml`
   - `--no-start`：只生成配置文件，不启动容器
   - `--no-health-check`：启动后跳过健康检查

3. 部署完成后浏览器打开 **http://localhost**，看到登录页即成功。

4. 用超级用户登录后，进入「系统设置 > 数据源设置」填写 Tushare token
   （Tavily / NewsAPI 可选），核心功能方可使用。

## 四、日常启动与关闭

```bash
# 启动（配置已存在时直接执行即可，自动拉起 Docker Desktop）
bash scripts/deploy_mac_local/deploy.sh

# 关闭（默认保留全部数据）
bash scripts/deploy_mac_local/stop.sh

# 关闭并删除全部数据卷（数据库、记忆、索引不可恢复，慎用）
bash scripts/deploy_mac_local/stop.sh -v

# 关闭并退出 Docker Desktop（释放内存）
bash scripts/deploy_mac_local/stop.sh --quit-docker
```

## 五、常用运维命令

```bash
docker compose ps                      # 查看服务状态
docker compose logs -f backend         # 跟踪后端日志
docker compose logs -f litellm         # 跟踪 LLM 网关日志
docker compose up -d --force-recreate backend   # 改配置后重建单个服务
scripts/database-maintenance.sh backup # 数据库备份
```

## 六、资源占用参考

- 内存：容器实际常驻合计约 4–6GB，加 Docker Desktop 虚拟机开销后整机约 5–8GB；
  硬上限 26GB（各容器 mem_limit 总和），AI 批量分析/抓取并发时接近上限。
- 磁盘：镜像约 10–15GB，数据卷 2–5GB（随使用增长），总计约 15–25GB。
- CPU：日常 <5%，AI 任务时多核打满（sandbox/webfetch/scrapling 各限 4 核）。

## 七、开发调试衔接

需要改代码调试时，使用 dev 栈（源码挂载 + 热重载），配置与本脚本共用：

```bash
# 1. 生成配置（不启动）
bash scripts/deploy_mac_local/deploy.sh --no-start

# 2. 启动 dev 栈（首次构建镜像较慢）
docker compose -f docker-compose.dev.yml up -d --build

# 3. 改后端 app/ 自动 reload；改前端 src/ 即时热更新；访问 http://localhost
```

注意：dev 栈与生产栈共用 project 名 `bat`，二者不能同时运行；
停止 dev 栈用 `docker compose -f docker-compose.dev.yml down`。

## 八、常见问题

| 现象 | 处理 |
| --- | --- |
| 提示缺少 SUPERUSER_PASSWORD / LLM_API_KEY | 检查 `deploy.conf` 是否已填写并保存 |
| 检测到已有配置文件报错 | 确认覆盖加 `--overwrite` |
| LLM 校验失败（HTTP 非 200） | 检查 API Key 完整性、模型名拼写、账号额度 |
| Docker 引擎未运行 | 脚本会自动拉起 Docker Desktop 并等待 2 分钟 |
| 镜像拉取很慢 | 可在 Docker Desktop → Docker Engine 配置国内镜像加速 |
| 容器反复重启 | 内存不足，检查 Docker Desktop 内存是否已调至 10–12GB |
| 关闭后数据还在吗 | 默认保留；`-v` 才会删除数据卷 |
