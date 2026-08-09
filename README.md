# Harmony LLM Chat Categorize

基于 HarmonyOS NEXT 的 AI 聊天应用，支持流式对话、深度思考、联网搜索、历史会话持久化与对话分类管理。

## 技术栈

- **平台**: HarmonyOS NEXT (API 20 / 6.0.0)
- **语言**: ArkTS
- **UI 框架**: ArkUI 声明式开发（LazyForEach 懒加载）
- **数据持久化**: `@kit.ArkData` relationalStore 关系型数据库 + Preferences 配置存储
- **凭据安全**: `@kit.AssetStoreKit` 加密存储 API Key（AES256-GCM，密钥存于 TEE，不参与云同步）
- **网络**: `@kit.NetworkKit` (HTTP SSE 流式请求 / Web Search API)
- **大模型 API**: OpenAI 兼容接口（默认 DeepSeek，Provider 工厂可扩展）
- **搜索 API**: 博查 AI Web Search API（国内直连，Provider 工厂可扩展）

## 功能特性

- **流式 AI 对话** — SSE 逐字输出，思考内容（reasoning_content）与正文分通道展示
- **深度思考（可开关）** — DeepSeek 官方 thinking 格式（enabled/disabled），开启时 reasoning_effort=max，关闭时强制不思考（V4 默认会思考，必须显式控制）
- **联网搜索** — 博查 Web Search 实时联网，结果作为参考资料驱动回答，失败自动降级
- **设置页** — 应用内填写 API 地址 / Key / 模型，保存后持久化，重启不丢失
- **密钥安全存储** — API Key 存入 Asset Store Kit（TEE 加密落盘，密文不写盘），旧版明文自动迁移并清除
- **多级文件夹分类** — 无限层级文件夹，收藏 Tab 显示顶级文件夹，支持进入下一级浏览
- **文件夹管理** — 新建 / 重命名 / 移动 / 删除（二次确认 + 级联移除分类关系），图标 8 色可选
- **对话归档** — 对话可移动到任意文件夹或移出不分类，按文件夹维度浏览
- **历史会话** — 对话自动持久化，侧边栏按时间分组展示（今天/昨天/7天内/30天内/年月）
- **会话管理** — 搜索过滤、长按菜单（多选/删除）、批量删除、左边缘右滑进入历史页
- **消息持久化** — 用户消息/AI 回复（含思考内容）实时入库，支持历史加载回看
- **智能滚动** — 自动跟随最新消息；用户手动滚动时暂停跟随
- **流式节流** — 增量文本 50ms 节流合并刷新，高频流式更新降到 ~20fps
- **多对话并发流式** — 每个对话独立 StreamTask，切换对话后原流在后台继续，互不串写
- **流式中断** — 支持中断/取消进行中的流式回复，页面销毁时自动清理定时器防泄漏
- **后台流式保活** — 退后台且流式进行中时申请 dataTransfer 长时任务，SSE 连接不被系统冻结
- **键盘避让** — RESIZE 模式，键盘弹出自动钉底
- **智能时间分割线** — 消息间隔超过 10 分钟自动显示

## 项目结构

```
ChatCategorize/
├── entry/src/main/
│   ├── ets/
│   │   ├── common/          # 全局常量与公共工具
│   │   │   ├── AppConstants.ets    # 颜色、字号、间距、提示文案
│   │   │   ├── Utils.ets           # 通用工具（generateId / showToast / 删除二次确认）
│   │   │   ├── TimeUtil.ets        # 时间分组与智能时间格式化
│   │   │   ├── Logger.ets          # 统一日志封装
│   │   │   └── NavTransitionManager.ets  # 页面跳转过渡动画
│   │   ├── config/          # 应用配置
│   │   │   ├── AppConfig.ets       # 配置管理（Preferences + Asset Store 读写）
│   │   │   └── SecureKeyStore.ets  # 密钥安全存储（Asset Store Kit 封装）
│   │   ├── database/        # 关系型数据库（DAO + Repository 分层）
│   │   │   ├── DatabaseHelper.ets          # 建表 + 共享 RdbStore
│   │   │   ├── ConversationDao.ets         # 对话表单表 CRUD
│   │   │   ├── MessageDao.ets              # 消息表单表 CRUD
│   │   │   ├── CategoryDao.ets             # 文件夹表单表 CRUD
│   │   │   ├── ConversationRepository.ets  # 对话+消息聚合 / 事务
│   │   │   └── CategoryRepository.ets      # 文件夹树 + 级联删除
│   │   ├── service/         # 服务层（Provider 工厂模式）
│   │   │   ├── LLMProviderFactory.ets      # 大模型 Provider 工厂
│   │   │   ├── SearchProviderFactory.ets   # 搜索 Provider 工厂
│   │   │   ├── StreamTask.ets              # 单个流式任务（缓冲/节流/占位消息隔离）
│   │   │   ├── BackgroundRunGuardService.ets # 后台长时任务保活（流式不被冻结）
│   │   │   └── provider/
│   │   │       ├── LLMProvider.ets         # 大模型抽象接口（SSE 流式）
│   │   │       ├── DeepSeekProvider.ets    # DeepSeek 实现（OpenAI 兼容）
│   │   │       ├── SearchProvider.ets      # 搜索抽象接口
│   │   │       └── BochaSearchProvider.ets # 博查搜索实现
│   │   ├── viewmodel/       # 状态管理层
│   │   │   ├── ChatViewModel.ets           # 聊天状态与消息流
│   │   │   ├── FolderViewModel.ets         # 文件夹树状态
│   │   │   └── SideBarViewModel.ets        # 侧边栏历史/收藏状态
│   │   ├── model/           # 数据模型
│   │   │   ├── Message.ets        # 消息模型（含思考/搜索状态）
│   │   │   ├── Conversation.ets   # 对话模型
│   │   │   ├── Category.ets       # 文件夹/分类模型
│   │   │   ├── FolderParams.ets   # 文件夹跳转参数
│   │   │   └── SideBarParams.ets  # 侧边栏路由参数（高亮当前对话）
│   │   ├── components/      # UI 组件（按职责分子目录）
│   │   │   ├── chat/               # 聊天相关
│   │   │   │   ├── MessageBubble.ets   # 聊天气泡（含思考块）
│   │   │   │   └── ChatInput.ets       # 输入栏（深度思考/联网开关）
│   │   │   ├── item/                # 列表项
│   │   │   │   ├── ConversationItem.ets  # 历史对话列表项（长按菜单）
│   │   │   │   └── FolderItem.ets        # 文件夹列表项（彩色图标）
│   │   │   └── dialog/              # 对话框
│   │   │       ├── RenameInputDialog.ets  # 通用文本输入对话框
│   │   │       ├── EditFolderDialog.ets   # 编辑文件夹对话框
│   │   │       └── FolderPickerDialog.ets # 文件夹选择器
│   │   ├── pages/           # 页面
│   │   │   ├── HomePage.ets       # 首页（导航入口）
│   │   │   ├── ChatPage.ets       # 主聊天页
│   │   │   ├── SideBarPage.ets    # 侧边栏（收藏/历史 Tab）
│   │   │   ├── FolderPage.ets     # 文件夹页（子文件夹+对话，可多级）
│   │   │   └── SettingsPage.ets   # 设置页（API 配置表单）
│   │   ├── entryability/    # Ability 入口
│   │   │   └── EntryAbility.ets   # onCreate 预加载配置
│   │   └── entrybackupability/    # 备份恢复能力
│   │       └── EntryBackupAbility.ets
│   └── module.json5         # 模块配置（含 INTERNET 权限）
├── build-profile.json5      # 构建配置（本地签名，不入库）
└── oh-package.json5         # 依赖管理
```

## 快速开始

### 1. 运行项目

使用 DevEco Studio 打开项目，连接设备或模拟器后点击运行。

### 2. 配置 API

应用内"设置"页填写（无需改代码，保存后持久化）：

| 字段          | 说明                                                                           |
| ------------- | ------------------------------------------------------------------------------ |
| API 地址      | 大模型接口，默认`https://api.deepseek.com/chat/completions`，OpenAI 兼容格式 |
| API Key       | 大模型密钥（密码输入框）                                                       |
| 模型名称      | 如`deepseek-v4-flash`                                                        |
| 搜索 API 地址 | 搜索渠道，默认`https://api.bochaai.com/v1/web-search`                        |
| 搜索 API 密钥 | 博查密钥，留空则不启用联网搜索                                                 |

- 大模型默认使用 DeepSeek，也支持任何 OpenAI 兼容 API
- 联网搜索基于博查 AI（[open.bochaai.com](https://open.bochaai.com) 注册获取 Key），国内直连免费
- ⚠️ 未配置时 AppConfig 各字段为空，聊天前会提示前往设置页

## 核心设计

### AppConfig — 配置管理（Preferences + Asset Store）

- 由 `EntryAbility.onCreate` 调用 `AppConfig.getInstance().init(context)` 幂等预加载
- **非敏感项**（baseUrl / model / searchBaseUrl）→ Preferences 明文存储
- **敏感项**（apiKey / searchApiKey）→ SecureKeyStore 加密存储，明文不写盘
- 旧版本迁移：检测 Preferences 遗留明文 Key，自动迁入 Asset Store 并删除明文残留
- `isConfigured()` 校验大模型三项是否齐全，未配置时聊天前拦截提示
- 默认配置为空字符串，**不硬编码任何密钥**

### SecureKeyStore — 密钥安全存储

- 基于 Asset Store Kit（类比 iOS Keychain / Android Keystore），密钥存入硬件安全区域（TEE）
- AES256-GCM 密文落盘，应用数据即使被读取/备份也无法还原明文
- `SyncType.NEVER`：不参与云同步 / 云备份，避免密钥随备份外泄
- 提供 `save` / `get` / `remove` 三个静态方法，空串保存视为清除旧密钥

### LLM Provider — SSE 流式对话（工厂模式）

```
用户输入 → ChatViewModel → LLMProviderFactory.create()
  → DeepSeekProvider.sendMessage()（HTTP POST, stream: true）
  → dataReceive 逐 chunk 解析 SSE
  → onReasoningChunk 输出思考内容（reasoning_content）
  → onChunk 输出正文
  → dataEnd / [DONE] 标记完成
```

- `LLMProvider` 定义抽象接口（流式回调），`DeepSeekProvider` 实现 OpenAI 兼容调用
- `LLMProviderFactory` 按渠道创建 Provider，新增模型只需实现接口并注册工厂
- SSE 不完整 chunk 缓冲处理、防止重复回调（isFinished 标记）
- 连接超时 15s，读取超时 60s
- 深度思考走 DeepSeek 官方格式：`thinking.enabled/disabled` + `reasoning_effort=max`，`deepThinking` 开关由 ChatInput 传入，关闭时显式 disabled（V4 模型默认思考，必须显式控制）

### Search Provider — 联网搜索（工厂模式）

```
开启联网 → ChatViewModel → SearchProviderFactory.create()
  → BochaSearchProvider.search()（博查 Web Search API POST）
  → 解析标题/URL/长摘要 → 拼接为 LLM 友好的 Markdown
  → 作为 system 消息插入上下文，驱动 LLM 基于资料回答
```

- `SearchProvider` 定义抽象接口，`BochaSearchProvider` 实现博查调用，与 LLM 完全解耦
- 返回 5 条结果，每条摘要截断 800 字符控制 token
- 搜索失败静默降级为普通对话，UI 显示降级提示

### DatabaseHelper — 关系型数据库（DAO + Repository 分层）

基于 `relationalStore`，三张表：

| 表               | 字段                                                      | 说明                          |
| ---------------- | --------------------------------------------------------- | ----------------------------- |
| `conversation` | id, title, category_id, created_at, updated_at            | 对话表                        |
| `message`      | id, conversation_id, role, content, reasoning, created_at | 消息表（含思考内容）          |
| `category`     | id, name, parent_id, color, sort_order, created_at        | 文件夹/分类表（支持多级嵌套） |

- 分层设计：`*Dao` 平铺单表 CRUD（异常上抛），`*Repository` 跨表聚合与事务（文件夹树、级联删除）
- 单例模式，`init()` 幂等建表（IF NOT EXISTS）
- 高频查询索引：`message(conversation_id)`、`conversation(updated_at DESC)`
- 对话延迟入库：首条用户消息时才创建对话记录，避免空白对话污染历史
- 删除对话级联删除消息（IN 条件）
- 文件夹树：`parent_id` 空串为顶级，`getCategorySubtreeIds()` 收集子孙节点，移动文件夹时排除自身防止成环
- 删除文件夹级联：`deleteCategoryCascade()` 先递归收集子孙，再移除其分类关系（对话本身不删除）
- 所有 API 调用 try-catch 包裹，异常静默降级

### ViewModel — 状态管理层

- `ChatViewModel`：聊天消息流、流式回调驱动 UI 更新、智能滚动状态
- `FolderViewModel`：文件夹树构建、多级导航、文件夹 CRUD 状态
- `SideBarViewModel`：历史会话分组、收藏 Tab、批量选择状态
- 页面与数据层解耦，通过 ViewModel 桥接 DAO/Repository 与 ArkUI 状态

### StreamTask — 多对话并发流式

- 一个进行中的流式任务 = 一个 `StreamTask` 实例（含正文/思考缓冲区、节流定时器、AI 占位消息）
- `ChatViewModel` 持有 `Map<conversationId, StreamTask>`：切到 B 对话后 A 对话的流在后台继续推进，缓冲互不串写
- 连发限制按"对话"粒度判断（`isStreamingFor`），不同对话的流互不影响
- 异步操作（加载对话/查标题）均带"过期结果守卫"：await 后校验对话 id 未变，防止快速切换导致 UI 错乱
- 页面销毁时遍历任务 `clearTimer()` 清理定时器，防止残留定时器触发过期写入

### BackgroundRunGuardService — 后台流式保活

- 背景：系统对退后台应用约 2 秒冻结网络、约 12 秒释放资源，SSE 流式连接会被掐断
- 解法：应用在后台**且**仍有流式任务时，申请 `dataTransfer` 长时任务（`backgroundTaskManager.startBackgroundRunning`），保持网络连接
- 任务全部结束或回到前台时立即 `stopBackgroundRunning` 释放，避免资源占用
- 前置配置：`ohos.permission.KEEP_BACKGROUND_RUNNING` 权限 + EntryAbility `backgroundModes: ["dataTransfer"]`
- ChatViewModel 通过 `updateStreamingTaskCount` 同步任务数，EntryAbility 的 onForeground/onBackground 切换后台状态

### ChatPage — 渲染优化

- **LazyForEach**（方案 C）：自定义 `IDataSource` 懒加载，只渲染可视区域消息
- **流式节流**（方案 A）：增量文本攒入缓冲区，每 50ms 合并刷新一次
- **页面过渡动画**：ChatPage 与 SideBarPage 左右平移推入

### 数据模型

| 模型             | 说明                                                                     |
| ---------------- | ------------------------------------------------------------------------ |
| `Message`      | 单条消息（@Observed 可观察），含 reasoning/isThinking/isSearching 等状态 |
| `Conversation` | 一个对话会话，可归属于某个 Category（文件夹）                            |
| `Category`     | 文件夹/分类（@Observed），含 parentId（多级嵌套）与 color（图标颜色）    |
