# Harmony LLM Chat Categorize

> **简体中文 | [English](README_EN.md)**

基于 HarmonyOS NEXT 的 AI 聊天应用，支持 SSE 流式对话、深度思考、联网搜索、历史会话持久化与多级文件夹分类管理，架构采用 MVVM + 分层设计，代码使用 ArkTS / ArkUI 声明式开发。

## 技术栈

| 维度         | 选型                                                                 |
| ------------ | -------------------------------------------------------------------- |
| 平台         | HarmonyOS NEXT 6.0.0（API 20，targetSdkVersion / compatibleSdkVersion） |
| 语言         | ArkTS（强类型 + 声明式）                                              |
| UI 框架      | ArkUI 声明式开发（@State / @Observed 状态管理，LazyForEach 懒加载）  |
| 数据持久化   | `@kit.ArkData` relationalStore 关系型数据库 + Preferences 配置存储   |
| 凭据安全     | `@kit.AssetStoreKit` 加密存储 API Key（AES256-GCM，密钥存于 TEE）    |
| 网络         | `@kit.NetworkKit`（HTTP SSE 流式请求 / Web Search API）              |
| 大模型 API   | OpenAI 兼容接口（默认 DeepSeek，Provider 工厂模式可扩展）            |
| 搜索 API     | 博查 AI Web Search API（国内直连，Provider 工厂模式可扩展）          |
| Markdown 渲染 | `@luvi/lv-markdown-in` 原生渲染（LaTeX 公式、代码高亮、Mermaid 图表） |

## 功能特性

- **流式 AI 对话** — SSE 逐字输出，思考内容（`reasoning_content`）与正文分通道展示
- **深度思考（可开关）** — 使用 DeepSeek 官方 thinking 格式，开启时 `reasoning_effort=max`，关闭时显式禁用（V4 默认思考，必须显式控制）
- **联网搜索** — 博查 Web Search 实时搜索，结果作为参考材料注入上下文驱动回答，失败自动降级为普通对话
- **设置页** — 应用内填写 API 地址 / Key / 模型，保存后持久化，重启不丢失
- **密钥安全存储** — API Key 经 Asset Store Kit（TEE）加密落盘，明文不写盘；旧版本明文自动迁移并清除
- **多级文件夹分类** — 无限层级文件夹，收藏 Tab 展示顶级文件夹，支持逐级下钻浏览
- **文件夹管理** — 新建 / 重命名 / 移动 / 删除（二次确认 + 级联移除分类关系），图标 8 色可选
- **对话归档** — 对话可移动到任意文件夹或移出不分类，按文件夹维度浏览
- **历史会话** — 对话自动持久化，侧边栏按时间分组（今天 / 昨天 / 7 天内 / 30 天内 / 年月）
- **会话管理** — 搜索过滤、长按菜单（多选 / 删除）、批量删除、左边缘右滑进入历史页
- **消息持久化** — 用户消息与 AI 回复（含思考内容）实时入库，支持历史加载回看
- **智能滚动** — 自动跟随最新消息，Markdown 异步渲染增高；用户手动滚动时暂停跟随
- **流式节流** — 增量文本 50ms 节流合并刷新，高频流式更新降至约 20fps
- **多对话并发流式** — 每个对话独立 StreamTask，切换对话后原流在后台继续，缓冲互不串写
- **流式中断** — 支持中断 / 取消进行中的流式回复，页面销毁时自动清理定时器防泄漏
- **后台流式保活** — 退后台且有流式任务时申请 `dataTransfer` 长时任务，SSE 连接不被系统冻结
- **键盘避让** — RESIZE 模式，键盘弹出时输入栏自动钉底
- **智能时间分割线** — 消息间隔超过 10 分钟自动显示
- **Markdown 渲染** — AI 消息原生渲染 Markdown（LaTeX 公式、代码高亮、Mermaid 图表），流式输出增量自动重绘
- **Markdown 渲染性能优化** — 屏幕外块懒渲染 + 线程渲染，仅预渲染可视区附近块；超长代码块自动折叠并显示行号；Markdown 库预热消除历史对话首次打开卡顿
- **Markdown 深色模式适配** — 完全跟随系统深浅色：代码块 / Mermaid 主题、LaTeX 公式颜色随 colorMode 动态切换，字体色走 `$r()` 资源引用
- **文本选中复制** — AI 消息长按选中一键复制（自行写入系统剪贴板），代码块右上角"复制"按钮，用户消息长按复制
- **对话分支** — AI 回复支持「重新生成」（覆盖当前回复）与「新建分支」（保留旧回复生成新变体），同组变体通过气泡底栏「当前 / 总数」循环切换，旧分支保留在库中随时可切回
- **消息编辑** — 用户消息「编辑」回填输入框（顶部显示编辑提示），发送后在该位置创建新分支并重新生成 AI 回复
- **删除单条消息** — 系统对话框二次确认后，级联删除该消息及其后续所有分支（子树整体删除）；全部删空时自动重置为新对话
- **选择文本（原文查看）** — AI 消息「更多」菜单打开底部半模态面板，展示渲染前的原始 Markdown 源码，支持长按选择 / 复制

## 快速开始

### 1. 运行项目

使用 DevEco Studio 打开项目根目录，等待依赖同步后连接真机或模拟器，点击 Run 即可。

### 2. 配置 API

应用内进入"设置"页填写（无需改代码，保存后持久化）：

| 字段          | 说明                                                                        |
| ------------- | --------------------------------------------------------------------------- |
| API 地址      | 大模型接口地址，默认 `https://api.deepseek.com/chat/completions`（OpenAI 兼容格式） |
| API Key       | 大模型密钥（密码输入框，加密存储）                                          |
| 模型名称      | 例如 `deepseek-v4-flash`                                                    |
| 搜索 API 地址 | 搜索接口地址，默认 `https://api.bochaai.com/v1/web-search`                  |
| 搜索 API 密钥 | 博查密钥，留空则不启用联网搜索                                              |

- 大模型默认使用 DeepSeek，任何 OpenAI 兼容 API 均可直接替换
- 联网搜索基于博查 AI（[open.bochaai.com](https://open.bochaai.com) 注册获取 Key），国内直连
- ⚠️ 未配置时聊天前会拦截提示，引导前往设置页

## 项目结构

```
ChatCategorize/
├── AppScope/                 # 应用级配置（应用图标、app.json5）
├── entry/src/main/
│   ├── ets/
│   │   ├── common/           # 全局常量与公共工具
│   │   │   ├── AppConstants.ets          # 业务常量（文件夹色板、气泡宽度比等）
│   │   │   ├── Utils.ets                 # 通用工具（generateId / showToast / 删除二次确认）
│   │   │   ├── TimeUtil.ets              # 时间分组与智能时间格式化
│   │   │   ├── Logger.ets                # 统一日志封装
│   │   │   └── NavTransitionManager.ets  # 页面跳转过渡动画
│   │   ├── config/           # 应用配置
│   │   │   ├── AppConfig.ets             # 配置管理（Preferences + Asset Store 读写）
│   │   │   └── SecureKeyStore.ets        # 密钥安全存储（Asset Store Kit 封装）
│   │   ├── database/         # 数据持久化层（DAO + Repository 分层）
│   │   │   ├── DatabaseHelper.ets        # 建表 + 共享 RdbStore 单例
│   │   │   ├── ConversationDao.ets       # 对话表单表 CRUD
│   │   │   ├── MessageDao.ets            # 消息表单表 CRUD
│   │   │   ├── CategoryDao.ets           # 文件夹表单表 CRUD
│   │   │   ├── ConversationRepository.ets# 对话 + 消息跨表聚合 / 事务
│   │   │   └── CategoryRepository.ets    # 文件夹树构建 + 级联删除
│   │   ├── service/          # 服务层（Provider 工厂模式）
│   │   │   ├── LLMProviderFactory.ets    # 大模型 Provider 工厂
│   │   │   ├── SearchProviderFactory.ets # 搜索 Provider 工厂
│   │   │   ├── StreamTask.ets            # 单个流式任务（缓冲 / 节流 / 占位消息隔离）
│   │   │   ├── BackgroundRunGuardService.ets # 后台长时任务保活
│   │   │   └── provider/
│   │   │       ├── LLMProvider.ets       # 大模型抽象接口（SSE 流式）
│   │   │       ├── DeepSeekProvider.ets  # DeepSeek 实现（OpenAI 兼容）
│   │   │       ├── SearchProvider.ets    # 搜索抽象接口
│   │   │       └── BochaSearchProvider.ets # 博查搜索实现
│   │   ├── viewmodel/        # 状态管理层（MVVM 的 VM）
│   │   │   ├── ChatViewModel.ets         # 聊天状态与消息流
│   │   │   ├── FolderViewModel.ets       # 文件夹树状态
│   │   │   └── SideBarViewModel.ets      # 侧边栏历史 / 收藏状态
│   │   ├── model/            # 数据模型（@Observed 可观察对象）
│   │   │   ├── Message.ets               # 消息模型（含思考 / 搜索状态与分支字段）
│   │   │   ├── Conversation.ets          # 对话模型
│   │   │   ├── Category.ets              # 文件夹 / 分类模型
│   │   │   ├── FolderParams.ets          # 文件夹跳转参数
│   │   │   └── SideBarParams.ets         # 侧边栏路由参数
│   │   ├── components/       # UI 组件（按职责分子目录）
│   │   │   ├── chat/                     # 聊天相关
│   │   │   │   ├── MessageBubble.ets     # 聊天气泡（含思考块与操作栏）
│   │   │   │   └── ChatInput.ets         # 输入栏（深度思考 / 联网开关）
│   │   │   ├── item/                     # 列表项
│   │   │   │   ├── ConversationItem.ets  # 历史对话列表项（长按菜单）
│   │   │   │   └── FolderItem.ets        # 文件夹列表项（彩色图标）
│   │   │   └── dialog/                   # 对话框
│   │   │       ├── RenameInputDialog.ets # 通用文本输入对话框
│   │   │       ├── EditFolderDialog.ets  # 编辑文件夹对话框
│   │   │       └── FolderPickerDialog.ets# 文件夹选择器
│   │   ├── pages/            # 页面（ArkUI 路由页面）
│   │   │   ├── HomePage.ets              # 首页（导航入口）
│   │   │   ├── ChatPage.ets              # 主聊天页
│   │   │   ├── SideBarPage.ets           # 侧边栏（收藏 / 历史 Tab）
│   │   │   ├── FolderPage.ets            # 文件夹页（子文件夹 + 对话，可多级）
│   │   │   └── SettingsPage.ets          # 设置页（API 配置表单）
│   │   ├── entryability/     # Ability 入口
│   │   │   └── EntryAbility.ets          # onCreate 预加载配置，前后台切换保活
│   │   └── entrybackupability/           # 备份恢复能力
│   │       └── EntryBackupAbility.ets
│   ├── resources/            # 资源文件（string / color / float / media / profile）
│   └── module.json5          # 模块配置（INTERNET / KEEP_BACKGROUND_RUNNING 权限）
├── build-profile.json5       # 构建配置（本地签名，不入库）
├── oh-package.json5          # 根依赖管理
└── hvigorfile.ts             # 构建脚本
```

## 核心设计

### 1. AppConfig — 配置管理（Preferences + Asset Store）

- 由 `EntryAbility.onCreate` 调用 `AppConfig.getInstance().init(context)` 幂等预加载
- **非敏感项**（baseUrl / model / searchBaseUrl）→ Preferences 明文存储
- **敏感项**（apiKey / searchApiKey）→ SecureKeyStore 加密存储，明文不写盘
- 旧版本迁移：检测 Preferences 遗留的明文 Key，自动迁入 Asset Store 并删除明文残留
- `isConfigured()` 校验大模型三项是否齐全，未配置时聊天前拦截提示
- 默认配置为空字符串，**不硬编码任何密钥**

### 2. SecureKeyStore — 密钥安全存储

- 基于 Asset Store Kit（类比 iOS Keychain / Android Keystore），密钥存入硬件安全区域（TEE）
- AES256-GCM 密文落盘，应用数据即使被读取 / 备份也无法还原明文
- `SyncType.NEVER`：不参与云同步 / 云备份，避免密钥随备份外泄
- 提供 `save` / `get` / `remove` 三个静态方法，空串保存视为清除旧密钥

### 3. LLM Provider — SSE 流式对话（工厂模式）

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
- SSE 不完整 chunk 缓冲处理，`isFinished` 标记防止重复回调
- 连接超时 15s，读取超时 60s
- 深度思考走 DeepSeek 官方格式：`thinking.enabled/disabled` + `reasoning_effort=max`，`deepThinking` 开关由 ChatInput 传入

### 4. Search Provider — 联网搜索（工厂模式）

```
开启联网 → ChatViewModel → SearchProviderFactory.create()
  → BochaSearchProvider.search()（博查 Web Search API POST）
  → 解析标题 / URL / 长摘要 → 拼接为 LLM 友好的 Markdown
  → 作为 system 消息插入上下文，驱动 LLM 基于资料回答
```

- `SearchProvider` 定义抽象接口，`BochaSearchProvider` 实现博查调用，与 LLM 完全解耦
- 返回 5 条结果，每条摘要截断 800 字符控制 token
- 搜索失败静默降级为普通对话，UI 显示降级提示

### 5. DatabaseHelper — 关系型数据库（DAO + Repository 分层）

基于 `relationalStore`，三张表：

| 表             | 字段                                                                                          | 说明                              |
| -------------- | --------------------------------------------------------------------------------------------- | --------------------------------- |
| `conversation` | id, title, category_id, created_at, updated_at                                                | 对话表                            |
| `message`      | id, conversation_id, role, content, reasoning, created_at, parent_id, branch_group_id, variant_index, is_active | 消息表（含思考内容与分支字段）    |
| `category`     | id, name, parent_id, color, sort_order, created_at                                            | 文件夹 / 分类表（支持多级嵌套）   |

- 分层设计：`*Dao` 平铺单表 CRUD（异常上抛），`*Repository` 跨表聚合与事务（文件夹树、级联删除）
- 单例模式，`init()` 幂等建表（IF NOT EXISTS）
- 旧库兼容：message 表缺少分支字段时，`ensureMessageColumns()` 通过 ALTER TABLE 幂等补列
- 高频查询索引：`message(conversation_id)`、`conversation(updated_at DESC)`
- 对话延迟入库：首条用户消息时才创建对话记录，避免空白对话污染历史
- 删除对话级联删除消息（IN 条件）；删除文件夹时 `deleteCategoryCascade()` 递归收集子孙后移除分类关系（对话本身不删除）
- 所有 API 调用 try-catch 包裹，异常静默降级

### 6. ViewModel — 状态管理层

- `ChatViewModel`：聊天消息流、流式回调驱动 UI 更新、智能滚动、对话分支（重新生成 / 新建分支 / 编辑 / 切换）
- `FolderViewModel`：文件夹树构建、多级导航、文件夹 CRUD 状态
- `SideBarViewModel`：历史会话分组、收藏 Tab、批量选择状态
- 页面与数据层解耦，通过 ViewModel 桥接 DAO / Repository 与 ArkUI 状态（MVVM 核心）

### 7. StreamTask — 多对话并发流式

- 一个进行中的流式任务 = 一个 `StreamTask` 实例（含正文 / 思考缓冲区、节流定时器、AI 占位消息）
- `ChatViewModel` 持有 `Map<conversationId, StreamTask>`：切到 B 对话后 A 对话的流在后台继续推进，缓冲互不串写
- 连发限制按"对话"粒度判断（`isStreamingFor`），不同对话的流互不影响
- 异步操作（加载对话 / 查标题）均带"过期结果守卫"：await 后校验对话 id 未变，防止快速切换导致 UI 错乱
- 页面销毁时遍历任务 `clearTimer()` 清理定时器，防止残留定时器触发过期写入

### 8. 对话分支 — 分支链模型

每条消息记录 `parentId`（被回复的消息，根用户消息为空串）、`branchGroupId`（= parentId，同组消息互为变体兄弟）、`variantIndex`（组内变体序号，0 起）、`isActive`（是否位于当前激活分支链，列表仅渲染激活链）：

```
U1(root) ── A1 (variant 0) ── U2 ── A2          ← 激活链（高亮）
   │           └ A1' (variant 1)                  ← 同组变体（熄灭，可切回）
```

- **重新生成**（`regenerateMessage`）：直接覆盖当前 AI 回复重新生成，不产生新变体
- **新建分支**（`createBranch`）：创建同父新变体并重新生成，旧回复及其后续链整条熄灭（`deactivateBranchFrom`）但保留在数据库
- **消息编辑**（`startEdit` / `editUserMessage`）：「编辑」回填输入框（`editingMessageId` + `editingPrefill`），发送时创建新用户消息变体并重新生成 AI 回复
- **删除单条消息**（`deleteMessage`）：沿 parentId 广度遍历收集该消息 + 全部后代 → 从 DB 与内存缓存同步删除 → 被删消息正在流式输出时先中止对应流任务 → 列表重建；全部删空时重置为新对话
- **切换分支**（`switchBranch`）：在分支组内按 ±1 循环切换变体，`rebuildActiveChain()` 全量熄灭 → 点亮目标变体祖先路径 → 延伸其激活后续链 → 持久化 → 重载列表
- **变体计数**（`getVariantInfo`）：返回 `{ current, total }` 驱动气泡底栏「当前 / 总数」，多变体时显示
- `allMessages` 缓存当前对话全量消息（含非激活变体），作为分支切换 / 变体统计 / 激活链重建的唯真源
- 兼容旧数据：全部消息 `parentId` 为空时按时间正序渲染，分支功能不影响原有体验
- 流式回复中操作栏整体隐藏（`message.isStreaming` 为 @Trace），从根源避免流式中误操作

### 9. BackgroundRunGuardService — 后台流式保活

- 背景：系统对退后台应用约 2 秒冻结网络、约 12 秒释放资源，SSE 流式连接会被掐断
- 解法：应用在后台**且**仍有流式任务时，申请 `dataTransfer` 长时任务（`backgroundTaskManager.startBackgroundRunning`），保持网络连接
- 任务全部结束或回到前台时立即 `stopBackgroundRunning` 释放，避免资源占用
- 前置配置：`ohos.permission.KEEP_BACKGROUND_RUNNING` 权限 + EntryAbility `backgroundModes: ["dataTransfer"]`

### 10. ChatPage — 渲染优化

- **LazyForEach**：自定义 `IDataSource` 懒加载，只渲染可视区域消息
- **流式节流**：增量文本攒入缓冲区，每 50ms 合并刷新一次
- **智能滚动（平滑跟随）**：流式跟随改为 50ms 防抖 + 200ms EaseOut 平滑动画（`scrollToBottomSmooth`，动画由页面注入 `getUIContext().animateTo` 执行），消除流式逐字刷新时的瞬移感；同时间只有一组动画，避免动画堆积抖动
- **滚动定位优先 scrollEdge**：`scrollToBottom()` 优先 `scrollEdge(Edge.Bottom)` 直达底部边缘（不依赖末尾 item 是否已懒加载渲染，更可靠），个别平台不支持时回退 `scrollToIndex(末尾, END)`
- **加载后多次钉底重试**：`pinToBottomAfterLoad()` 以 120ms 间隔重试最多 6 次，解决"分支多、Markdown 渲染重的对话打开时滚不到最后一条"（懒加载 + Markdown 异步渲染导致 item 高度后知后觉）
- **首帧布局挂起**：List 首次 `onAreaChange` 触发 `onListFirstLayout()`；布局未就绪前的钉底请求先挂起（`pendingPinToBottom`），避免从侧边栏返回的转场期间"打开瞬间停留在列表顶部"
- **消息项高度变化即时钉底**：ListItem `onAreaChange` 上报高度增量（`onListItemHeightChanged`），Markdown 异步渲染增高时立即重新钉底，比固定间隔重试响应更快且无空转；流式期间跳过，交由动画跟随统一处理
- **Markdown 库预热**：ChatPage 内置一个 `Visibility.Hidden` + 零尺寸的 `Markdown` 组件，提前触发 lv-markdown-in 的 worker 初始化（进程内单例），消除历史对话首次打开时"正文卡顿"
- **页面过渡动画**：ChatPage 与 SideBarPage 左右平移推入
- **返回键拦截**：ChatPage 是栈底主页面（isEntry 入栈），系统返回键 = 退出应用；`onBackPressed` 拦截后 `terminateSelf()` 直接退出，避免 NavDestination 被弹出回到空白的 Navigation 首页

### 11. MessageBubble — Markdown 渲染与文本交互

- AI 消息正文由 `@luvi/lv-markdown-in` 的 `Markdown` 组件原生渲染（完整 markdown 语法、LaTeX 公式、代码高亮，mermaid 由库内置处理，无需自建 WebView）；用户消息保持纯文本（气泡宽度自适应）
- **渲染性能优化**：`setLazyRender(true)` + `setLazyPreloadBlockCount(2)` 让屏幕外块先以轻量占位渲染、仅预渲染可视区附近少量块；`setThreadRenderEnable(true)` 开启线程渲染；`setCodeBlockIdxState(true)` 为代码块显示行号、`setCodeBlockAutoCollapseEnable(true)` 让超过阈值（默认 10 行）的代码块自动折叠，缓解长代码块渲染压力
- **深色模式适配**：字体色走 `$r()` 资源引用（系统自动加载 dark/ 目录对应色值）；代码块 / Mermaid 主题与 LaTeX 公式颜色通过 `on('environment')` 监听 colorMode 动态切换，`aboutToDisappear` 注销监听防泄漏
- **文本复制**：`setTextSelectionEnable(true)` 开启长按选中 + `setTextSelectionCopyListener` 自行写入系统剪贴板（成功 / 失败均有 Toast）；代码块通过 `setCodeCopyListener` 注册"复制"按钮；用户消息通过 `copyOption(CopyOptions.LocalDevice)` 长按复制
- **底部操作栏**：用户消息 [删除] [复制] [编辑] [切换分支]；AI 消息 [切换分支] [复制] [更多] 与 [删除] [新建分支] [重新生成]；「更多」弹纵向菜单：复制 / 选择文本 / 新建分支 / 重新生成 / 删除（红色警示置底）；多变体时显示「当前 / 总数」切换控件
- **选择文本（原文查看）**：「更多」→「选择文本」通过 `bindSheet($$isTextSheetShow)` 弹出底部半模态面板，展示渲染前的原始 Markdown 源码（`copyOption(CopyOptions.LocalDevice)` 长按选择 / 复制）；面板高度 = 窗口高 − 状态栏 − 标题栏，与页面标题栏下缘对齐，$$ 双向绑定保证关闭时状态自动复位
- **删除消息**：垃圾桶按钮点击弹系统对话框二次确认（`result.index === 1` 才真正删除），确认后由 ViewModel 沿 parentId 级联删除
- 流式输出时 `text` 为 @Prop，chunk 增量自动重绘；`Message.isStreaming` 标记进行中状态，结束（含异常）时清除

## 数据模型

| 模型           | 说明                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------- |
| `Message`      | 单条消息（@Observed 可观察），含 reasoning / isThinking / isSearching 等状态；分支字段 parentId / branchGroupId / variantIndex / isActive |
| `Conversation` | 一个对话会话，可归属于某个 Category（文件夹）                                            |
| `Category`     | 文件夹 / 分类（@Observed），含 parentId（多级嵌套）与 color（图标颜色）                  |

## 权限说明

| 权限                              | 用途                         |
| --------------------------------- | ---------------------------- |
| `ohos.permission.INTERNET`        | 发起 LLM / 搜索网络请求      |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台保持流式连接不被冻结 |
