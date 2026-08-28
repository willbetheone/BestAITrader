# 天枢智投（BestAITrader）初学者入门书

> 面向初学者的项目全解析：结构、功能、架构、亮点，以及 LangChain / LangGraph 的实战用法。
> 建议配合源码阅读，文中所有路径均可在仓库中直接定位。

---

## 第一章 项目是什么

天枢智投是一个面向 **A 股投研** 的智能交易系统。它不是"把行情表包成聊天机器人"的 Demo，而是一套完整的 AI 投研操作系统：

> 让 LLM 从"会聊天的模型"升级为**能查数据、会分工、能辩论、可记忆、可审计、能执行、能复盘**的 AI 投研与交易团队。

系统由四大层构成：

| 层 | 职责 | 对应模块 |
| --- | --- | --- |
| 数据层 | 行情、财务、新闻、政策、情绪、资金流等真实上下文 | `backend/app/data` |
| Agent 层 | 多角色分工、工具调用、多轮辩论、结构化决策 | `backend/app/ai` |
| 交易层 | 模拟账户、订单、持仓、FIFO 批次账本、T+1 约束 | `backend/app/trading` |
| 记忆层 | 长期记忆（MemoFlux）与后验经验复盘 | `memo/` + `backend/app/ai/experience` |

**重要定位**：本项目用于研究与模拟交易，不构成投资建议。

---

## 第二章 全景架构：一张图看懂系统

### 2.1 服务拓扑（Docker Compose 一体化）

```
                        ┌─────────────┐
        浏览器 ────────► │    Nginx    │ 统一入口（80 端口）
                        └──────┬──────┘
                 ┌─────────────┼─────────────┐
                 ▼             ▼             ▼
           ┌──────────┐  ┌──────────┐  （静态资源）
           │ Frontend │  │ Backend  │
           │ React+TS │  │ FastAPI  │
           └──────────┘  └────┬─────┘
        ┌──────────┬──────────┼──────────┬───────────┐
        ▼          ▼          ▼          ▼           ▼
  ┌──────────┐┌────────┐┌─────────┐┌─────────┐┌─────────┐
  │PostgreSQL││ Redis  ││ LiteLLM ││ MemoFlux││ Sandbox │
  │ 业务数据 ││缓存/队列││ LLM 网关 ││ 长期记忆 ││Python沙箱│
  └──────────┘└────────┘└────┬────┘└────┬────┘└─────────┘
                             ▼          ▼
                      各家大模型   memo-postgres(pgvector)
```

此外还有独立的 **WebFetch** 网页渲染服务和可选的 **Scrapling MCP**。所有服务由一份 `docker-compose.yml` 拉起，这是本项目工程化程度的直接体现。

### 2.2 代码目录结构

```
BestAITrader/
├── backend/                    # FastAPI 后端（核心）
│   ├── app/
│   │   ├── ai/                 # ★ AI 核心，本书重点
│   │   │   ├── llm_engine/     #   多智能体辩论引擎（LangGraph 编排）
│   │   │   │   ├── orchestrator.py   # LangGraph 工作流定义
│   │   │   │   ├── agents/           # 各角色 Agent 实现
│   │   │   │   ├── prompts/          # 提示词模板
│   │   │   │   └── context/          # 上下文构建服务
│   │   │   ├── agentic/        #   工具层：tools、MCP、Skills
│   │   │   ├── stock_picker/   #   对话式智能选股
│   │   │   ├── stock_analysis/ #   个股深度分析
│   │   │   ├── experience/     #   后验经验复盘（第二个 LangGraph 工作流）
│   │   │   ├── market_watch/   #   AI 盯盘
│   │   │   └── llm_providers/  #   LLM 提供商抽象（走 LiteLLM）
│   │   ├── api/endpoints/      # REST + WebSocket 接口
│   │   ├── data/               # 数据工程（行情/财务/新闻采集）
│   │   ├── trading/            # 模拟交易引擎
│   │   ├── portfolio/          # 持仓账本
│   │   ├── risk_control/       # 风控
│   │   ├── models/ crud/ schemas/  # ORM / 数据访问 / DTO
│   │   └── websocket/          # 实时推送
│   └── tests/                  # 100+ 测试文件
├── frontend/                   # React + TypeScript + Vite 前端
├── memo/                       # MemoFlux 长期记忆服务（子模块）
├── sandbox/                    # 独立 Python 沙箱服务
├── webfetch/                   # 网页抓取/渲染服务
└── docker-compose.yml          # 一体化部署
```

**初学者记法**：`backend/app/ai` 是"大脑"，`app/data` 是"眼睛"，`app/trading` 是"手"，`memo` 是"记忆"。

---

## 第三章 核心功能盘点

| 功能 | 说明 | 入口文件 |
| --- | --- | --- |
| 多智能体辩论决策 | 14 个角色 Agent 分层分析 + 辩论 + PM 裁决 | `ai/llm_engine/orchestrator.py` |
| 对话式智能选股 | 自然语言提需求 → 计划卡片确认 → 研究 → 证据合成 | `ai/stock_picker/interactive_research/` |
| 模拟交易 | 账户/订单/成交/FIFO 账本/A 股一手与 T+1 | `app/trading/` |
| AI 盯盘 | 结构化持仓+行情喂给盯盘 AI，生成提醒 | `ai/market_watch/ai_gate.py` |
| 长期记忆 | 集成 MemoFlux，经验与偏好可召回、带证据 | `memo/` + `ai/agentic/memory_tools.py` |
| 经验复盘 | 用真实价格路径检验 PM 决策，教训写回记忆 | `ai/experience/workflow.py` |
| 实时可观测 | WebSocket 推送辩论过程，前端审计页可回放 | `api/endpoints/debate_ws.py` |
| Skills / MCP | Agent 可加载技能包、接入 MCP 工具服务 | `ai/agentic/skills_loader/`、`ai/agentic/mcp/` |

---

## 第四章 架构深入：一次"AI 投委会"是怎么开会的

这是全项目最核心的流程，理解它就理解了 80% 的系统。

### 4.1 角色分工（见 `llm_engine/roles.py`）

**第一层 · 垂直分析师（7 位，各看各的领域）**
基本面、技术面、资金流、情绪、风控、新闻、政策分析师。

**第二层 · 战略辩论（5 位）**
多头研究员（Bull）vs 空头研究员（Bear）先交锋，再由激进、保守、中立三位分析师交叉质询。

**治理层（2 位）**
事实仲裁员（Fact Arbitrator）裁定辩论中的事实分歧；组合经理（Portfolio Manager, PM）做最终结构化决策。

### 4.2 会议流程（LangGraph 状态图）

`orchestrator.py` 中的 `create_analyst_workflow()` 定义了这张图：

```
fetch_context（取上下文）
   │
   ├─► news_analysis ─► policy_analysis ─► sentiment_analysis
   │                                            │
   └─► vertical_analysis ◄──────────────────────┘
              │（5 位垂直分析师并行出报告）
              ▼
        layer1_gate（错误闸门：出错即终止）
              ▼
      strategic_round_1（多头 vs 空头）
              ▼
      strategic_round_2_1（激进/保守/中立交叉质询）
              ▼
       fact_arbitration（事实仲裁）
              ▼
     portfolio_management（PM 结构化决策）
```

**要点**：
- 每个节点是一个 `async` 函数，接收全局状态、返回部分状态更新；
- `add_conditional_edges` 实现"出错即停"的熔断路由；
- 每个 Agent 的报告会通过 `persist_agent_report()` 落库并经 WebSocket 推给前端，**全程可审计**。

### 4.3 单个 Agent 内部：工具调用循环（见 `agents/base.py`）

每个 Agent 都是"ReAct 式"的推理循环，最多 `MAX_LLM_ITERATIONS=60` 轮：

1. LLM 决定调工具还是直接输出；
2. 调工具 → 执行 → 结果作为 `ToolMessage` 回填对话；
3. 超长工具输出先用小模型**智能摘要**，防止上下文爆炸；
4. 想输出最终报告时还要过三道质检：
   - **最少迭代轮次**：不许偷懒，必须查够证据；
   - **Markdown 结构检查**：标题/章节/段落数量达标；
   - **角色级校验**：子类可自定义验收规则；
5. 需要结构化输出的角色（如 PM）用 `PydanticOutputParser` 解析，JSON 解析失败自动重试 3 次。

> 初学者洞察：这套"质检 + 重试 + 迭代预算"是工程级 Agent 与玩具 Demo 的分水岭。

---

## 第五章 LangChain 实战用法详解

本项目是 LangChain 的**重度实战案例**，主要用到以下能力：

### 5.1 Chat Model 抽象与多供应商接入

```python
# agents/base.py
self.llm = self.llm_provider.build_chat_model(
    model=self.model_name,
    temperature=self.temperature,
)
```

- 通过 `ai/llm_providers/` 工厂统一构建聊天模型，实际请求走 **LiteLLM 网关**（`litellm/`），一套代码可切换任意大模型；
- 自定义 `LiteLLMChatOpenAI` 处理 reasoning_content 回放等兼容性问题（见 `tests/test_litellm_provider.py`）。

### 5.2 Tool Calling（工具调用）

```python
self.tools = self.get_tools()               # 全局工具 + 记忆工具 + Skills 工具
self.llm_with_tools = self.llm.bind_tools(self.tools)   # ★ 关键一行
```

`bind_tools` 把工具 schema 注入模型，模型返回 `response.tool_calls`，代码逐个执行后把结果包成 `ToolMessage` 回填——这就是标准的 LangChain 工具循环。

工具清单（`ai/agentic/tools.py` 的 `get_all_tools()`）涵盖：
行情/财务数据查询（`query_stock_data`、`fetch_financial_data`）、市场数据同步、新闻检索、数据库 schema 自省（`get_database_schema`）、查询即计算（`query_and_calculate`）、**Python 沙箱执行**（`execute_python_sandboxed`，调用独立 sandbox 服务）、模拟下单（`execute_trading_order`，带 PM 交易闸门校验）等。

### 5.3 消息体系

全程使用 `SystemMessage`（角色设定）、`HumanMessage`（上下文/反馈）、`AIMessage`、`ToolMessage` 构建对话流。辩论中"上一轮报告"就是作为消息传给下一轮 Agent 的，实现了**角色间的信息接力**。

### 5.4 结构化输出

```python
parser = PydanticOutputParser(pydantic_object=output_model)
format_instructions = parser.get_format_instructions()   # 注入格式要求
result = parser.parse(final_content)                     # 解析为 Pydantic 对象
```

PM 决策、经验复盘三件套（信号验证/证伪/噪音分类、流程改进项）都用 Pydantic 模型强约束，保证下游代码能可靠消费。

### 5.5 上下文工程

- 上下文分为 **STATIC_CONTEXT**（本次工作流固定数据）与 **RUNTIME_CONTEXT**（当前轮次动态数据）两条消息注入，见 `_build_context_messages()`；
- 用 `tiktoken` 统计 token，控制上下文规模。

---

## 第六章 LangGraph 实战用法详解

### 6.1 为什么用 LangGraph 而不是手写循环

辩论流程是**多阶段、有分支、要熔断**的复杂流程。LangGraph 提供：
- **StateGraph + TypedDict 状态**：所有节点共享一个可类型检查的全局状态；
- **条件边（conditional edges）**：按运行时状态决定走哪条路；
- **可观测性**：每个节点进出清晰，便于调试与持久化。

### 6.2 状态定义

```python
# orchestrator.py
class AnalystState(TypedDict):
    stock_code: str
    trading_frequency: str
    trading_strategy: str
    session_id: Optional[UUID]
    static_context: Dict[str, Any]          # 固定上下文
    context: Dict[str, Any]                 # 运行时上下文
    sentiment_report / news_report / ...    # 第一层报告
    vertical_reports: Dict[str, str]
    strategic_reports: Dict[str, str]       # 辩论各轮报告
    fact_arbitration_report: Optional[str]
    pm_decision: str
    errors: Annotated[List[str], add]       # ★ Reducer：错误自动累加
```

**初学者重点**：`Annotated[List[str], add]` 是 LangGraph 的 **reducer 机制**——多个节点都往 `errors` 写时自动追加而非覆盖。

### 6.3 建图三件套

```python
workflow = StateGraph(AnalystState)
workflow.add_node("news_analysis", news_analysis)      # 节点 = 异步函数
workflow.set_entry_point("fetch_context")              # 入口
workflow.add_conditional_edges(                          # 条件路由
    "layer1_gate",
    lambda state: _halt_on_errors(state, "strategic_round_1"),
    {END: END, "strategic_round_1": "strategic_round_1"},
)
workflow.add_edge("vertical_analysis", "layer1_gate")   # 普通边
```

模式总结：**节点函数读 state → 调 Agent → 返回 `{字段: 新值}` 局部更新**。

### 6.4 项目中两处 LangGraph 工作流

1. **辩论决策**：`llm_engine/orchestrator.py`（第四章的流程图）；
2. **经验复盘**：`experience/workflow.py`——复盘 PM 决策对错、信号验证/证伪/噪音归类、流程改进建议，同样用 StateGraph 编排、工具循环取证，并把结论写回长期记忆。

---

## 第七章 其他亮点功能解析

### 7.1 对话式智能选股（Human-in-the-loop）

`stock_picker/interactive_research/` 实现了真正的人机协作：

- **plan_agent.py**：用户自然语言提需求 → 生成"研究计划卡片"供确认/修订，多轮对话式敲定计划；
- **research_agent.py**：批准后进入工具循环研究，支持**用户中途插话**（排队输入自动并入下一轮），并引入 `FLOW_CONTROL_TOOL` 流程控制工具协议——模型必须显式调用控制工具声明"继续/结束"，防止失控；
- **serializers.py**：把 plan_card / tool_start / tool_result / progress_update 等消息类型渲染成聊天流 Markdown；
- 全程消息持久化，断点可续。

### 7.2 长期记忆闭环（MemoFlux）

- 独立服务 `memo/`（自带 pgvector 向量库），Agent 通过 `memory_tools.py` 暴露的记忆工具读写；
- 经验复盘的教训、用户偏好、历史结论沉淀为**带证据、可召回**的记忆；
- 形成"分析 → 决策 → 执行 → 复盘 → 记忆 → 下次分析更好"的进化闭环。

### 7.3 可审计性设计

- 每个 Agent 的 prompt 输入（`last_prompt`）与报告都持久化到 `DebateMessage`；
- WebSocket（`debate_ws.py`）实时推送，前端辩论页面逐条展示；
- session / message / task / order / memory 事件全链路可追踪。

### 7.4 工程化亮点汇总

| 亮点 | 体现 |
| --- | --- |
| LLM 网关化 | LiteLLM 统一接入，可换模型、可记用量（`crud/llm_usage_log`） |
| 工具输出治理 | 长输出自动摘要（`tool_output_summarizer.py`），防上下文爆炸 |
| 输出质检 | 最少迭代、结构检查、JSON 重试三重把关 |
| 错误熔断 | LangGraph 条件边 + `_halt_on_errors`，任何阶段出错立即终止并落库 |
| 安全沙箱 | Python 计算在独立 sandbox 容器执行，主进程零风险 |
| 国际化 | `core/i18n` + `locales/`，Agent 名称/提示词随语言切换 |
| 测试覆盖 | `backend/tests/` 100+ 测试文件，辩论引擎有专门测试 |

---

## 第八章 前端与实时体验

- 技术栈：**React + TypeScript + Vite**，`frontend/src/`；
- 按领域划分 `features/`：`brain`（辩论大脑）、`stockPicker`（选股）、`trading`（交易）、`market`（行情）、`auth`；
- 关键页面：仪表盘、AI 选股、辩论会话、模拟交易、经验复盘、数据管理、系统设置；
- 辩论过程通过 WebSocket 实时渲染每个 Agent 的报告，实现"AI 开会全程直播"。

---

## 第九章 初学者学习路线（建议按序）

1. **先跑起来**：按 `docs/002-deployment.md` 用 Docker Compose 启动，浏览前端感受全貌；
2. **读 README**：理解"四层架构"和与传统 LLM Demo 的差异；
3. **跟一次辩论**：打开 `llm_engine/roles.py` 认角色 → 读 `orchestrator.py` 的 `create_analyst_workflow()` 看流程 → 读 `agents/base.py` 的 `run()` 看单 Agent 循环；
4. **学 LangChain**：重点掌握 `bind_tools`、消息体系、`PydanticOutputParser` 三件事；
5. **学 LangGraph**：理解 `StateGraph / add_node / add_conditional_edges / reducer` 四个概念，然后对照 `experience/workflow.py` 看第二个例子；
6. **看工具层**：`agentic/tools.py` 里挑 2-3 个工具读实现，理解"Agent 的手"；
7. **进阶**：研究 `interactive_research` 的人机协作协议和 `experience` 复盘闭环。

**一句话总结**：天枢智投用 LangGraph 编排"投委会流程"，用 LangChain 武装每个"委员"（工具 + 结构化输出 + 质检），用数据层喂真话、用记忆层攒经验——这就是现代 Agentic AI 系统的标准范式。

---

*文档版本：2026-08-21 · 基于当前仓库代码分析整理*
