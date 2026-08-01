# Harmony LLM Chat Categorize

基于 HarmonyOS NEXT 的 AI 聊天应用，支持流式对话、深度思考、联网搜索、历史会话持久化与对话分类管理。

## 技术栈

- **平台**: HarmonyOS NEXT (API 20 / 6.0.0)
- **语言**: ArkTS (TypeScript 严格模式)
- **UI 框架**: ArkUI 声明式开发（LazyForEach 懒加载）
- **数据持久化**: `@kit.ArkData` relationalStore 关系型数据库
- **网络**: `@kit.NetworkKit` (HTTP SSE 流式请求 / Web Search API)
- **大模型 API**: OpenAI 兼容接口（默认使用 DeepSeek）
- **搜索 API**: 博查 AI Web Search API（国内直连）

## 功能特性

- **流式 AI 对话** — SSE 逐字输出，思考内容（reasoning_content）与正文分通道展示
- **深度思考** — AI 推理过程可折叠展示，含思考耗时统计
- **联网搜索** — 博查 Web Search 实时联网，结果作为参考资料驱动回答，失败自动降级
- **历史会话** — 对话自动持久化，侧边栏按时间分组展示（今天/昨天/7天内/30天内/年月）
- **会话管理** — 搜索过滤、长按菜单（多选/删除）、批量删除、左边缘右滑进入历史页
- **消息持久化** — 用户消息/AI 回复（含思考内容）实时入库，支持历史加载回看
- **智能滚动** — 自动跟随最新消息；用户手动滚动时暂停跟随
- **流式节流** — 增量文本 50ms 节流合并刷新，高频流式更新降到 ~20fps
- **键盘避让** — RESIZE 模式，键盘弹出自动钉底
- **智能时间分割线** — 消息间隔超过 10 分钟自动显示
- **对话分类管理** — Category 模型与分类表（规划中）

## 项目结构

```
ChatCategorize/
├── entry/src/main/
│   ├── ets/
│   │   ├── common/          # 全局常量（颜色、字号、间距）
│   │   │   └── AppConstants.ets
│   │   ├── config/          # 应用配置（大模型 + 搜索 API）
│   │   │   └── AppConfig.ets
│   │   ├── database/        # 关系型数据库（建表 + CRUD）
│   │   │   └── DatabaseHelper.ets
│   │   ├── service/         # 网络服务层
│   │   │   ├── AIService.ets        # 大模型流式对话（SSE）
│   │   │   └── SearchService.ets    # 联网搜索（博查 API）
│   │   ├── model/           # 数据模型
│   │   │   ├── Message.ets        # 消息模型（含思考/搜索状态）
│   │   │   ├── Conversation.ets   # 对话模型
│   │   │   └── Category.ets       # 分类模型
│   │   ├── components/      # UI 组件
│   │   │   ├── MessageBubble.ets      # 聊天气泡（含思考块）
│   │   │   ├── ChatInput.ets          # 输入栏（深度思考/联网开关）
│   │   │   └── ConversationItem.ets   # 历史对话列表项（长按菜单）
│   │   ├── pages/           # 页面
│   │   │   ├── ChatPage.ets       # 主聊天页
│   │   │   └── SideBarPage.ets    # 侧边栏（收藏/历史 Tab）
│   │   └── entryability/    # Ability 入口
│   │       └── EntryAbility.ets
│   └── module.json5         # 模块配置（含 INTERNET 权限）
├── build-profile.json5      # 构建配置
└── oh-package.json5         # 依赖管理
```

## 快速开始

### 1. 配置 API Key

打开 `entry/src/main/ets/config/AppConfig.ets`，填入你的密钥：

```typescript
private config: ApiConfig = {
  baseUrl: "https://api.deepseek.com/chat/completions", // ← 大模型 API 地址
  apiKey: "你的API-Key",                                // ← 大模型 API Key
  model: "deepseek-v4-flash",                           // ← 大模型名称
  searchBaseUrl: "https://api.bochaai.com/v1/web-search", // ← 搜索渠道地址
  searchApiKey: "你的搜索API-Key",                        // ← 搜索 API Key
};
```

- 大模型默认使用 DeepSeek，也支持任何 OpenAI 兼容 API
- 联网搜索基于博查 AI（[open.bochaai.com](https://open.bochaai.com) 注册获取 Key），国内直连免费；Key 留空则自动隐藏搜索能力

### 2. 运行项目

使用 DevEco Studio 打开项目，连接设备或模拟器后点击运行。

## 核心设计

### AIService — SSE 流式对话

```
用户输入 → ChatPage 创建占位消息 → AIService.sendMessage()
  → HTTP POST (stream: true)
  → dataReceive 逐 chunk 解析 SSE
  → onReasoningChunk 输出思考内容（reasoning_content）
  → onChunk 输出正文
  → dataEnd / [DONE] 标记完成
```

- 单例模式，全局唯一实例
- SSE 不完整 chunk 缓冲处理
- 防止重复回调（isFinished 标记）
- 连接超时 15s，读取超时 60s

### SearchService — 联网搜索

```
开启联网 → ChatPage 调 SearchService.search()
  → 博查 Web Search API POST
  → 解析标题/URL/长摘要 → 拼接为 LLM 友好的 Markdown
  → 作为 system 消息插入上下文，驱动 LLM 基于资料回答
```

- 与 LLM 完全解耦，换任何模型不影响搜索
- 返回 5 条结果，每条摘要截断 800 字符控制 token
- 搜索失败静默降级为普通对话，UI 显示降级提示

### DatabaseHelper — 关系型数据库

基于 `relationalStore`，三张表：

| 表               | 字段                                                      | 说明                 |
| ---------------- | --------------------------------------------------------- | -------------------- |
| `conversation` | id, title, category_id, created_at, updated_at            | 对话表               |
| `message`      | id, conversation_id, role, content, reasoning, created_at | 消息表（含思考内容） |
| `category`     | id, name, sort_order, created_at                          | 分类表               |

- 单例模式，`init()` 幂等建表（IF NOT EXISTS）
- 高频查询索引：`message(conversation_id)`、`conversation(updated_at DESC)`
- 对话延迟入库：首条用户消息时才创建对话记录，避免空白对话污染历史
- 删除对话级联删除消息（IN 条件）
- 所有 API 调用 try-catch 包裹，异常静默降级

### ChatPage — 渲染优化

- **LazyForEach**（方案 C）：自定义 `IDataSource` 懒加载，只渲染可视区域消息
- **流式节流**（方案 A）：增量文本攒入缓冲区，每 50ms 合并刷新一次
- **页面过渡动画**：ChatPage 与 SideBarPage 左右平移推入

### AppConfig — 配置管理

当前为硬编码阶段，后续将替换为 `@ohos.data.preferences` 持久化存储。

### 数据模型

| 模型             | 说明                                                                     |
| ---------------- | ------------------------------------------------------------------------ |
| `Message`      | 单条消息（@Observed 可观察），含 reasoning/isThinking/isSearching 等状态 |
| `Conversation` | 一个对话会话，可归属于某个 Category                                      |
| `Category`     | 对话分类，支持侧边栏筛选                                                 |
