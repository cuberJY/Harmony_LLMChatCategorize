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
| 网络         | `@kit.NetworkKit`（HTTP SSE 流式请求，Responses API）            |
| 大模型 API   | DeepSeek Responses API（供应商预设注册表 + Provider 工厂模式可扩展） |
| 联网搜索     | DeepSeek 服务端 web_search 工具（本地不再调用第三方搜索 API）        |
| Markdown 渲染 | `@luvi/lv-markdown-in` 原生渲染（LaTeX 公式、代码高亮、Mermaid 图表） |

## 功能特性

- **流式对话** — SSE 逐字输出，思考内容与正文分通道展示，增量自动重绘
- **思考强度** — 关闭 / Low / High / Max 四档下拉（输入区按钮，样式同设置页），走 Responses API `reasoning.effort`
- **联网搜索** — 服务端 `web_search` 工具；搜索词与浏览网页实时可视化，支持「x 个网页」列表跳转
- **暂停 / 继续生成** — 生成中可中止并保留内容，网络异常自动暂停，一键续写；重启后可恢复未完成生成
- **结构化错误提示** — 错误卡片展示分类 + 文案 + 可展开详情，不污染正文
- **对话分支** — 换个回答 / 生成新回复 / 分支切换，旧分支保留在库可切回
- **消息编辑 / 删除** — 编辑后原位生成新分支；删除级联清理后续分支
- **文件夹分类** — 无限层级，新建 / 重命名 / 移动 / 删除，对话可归档；文件夹内对话支持多选批量操作（取消收藏 / 删除 / 移动到其他文件夹）
- **历史会话** — 自动持久化，侧边栏按时间分组，支持全局搜索 / 多选 / 批量删除
- **全局搜索** — 侧边栏放大镜入口弹出搜索面板，同时匹配对话标题与消息正文，结果按对话分组展示命中片段；可精确跳转定位到命中消息，支持「仅激活分支 / 全部历史分支」范围切换
- **密钥安全** — API Key 经 Asset Store Kit（TEE）加密落盘，旧版明文自动迁移
- **后台保活** — 退后台有流式任务时申请 `dataTransfer` 长时任务
- **系统备份 / 恢复** — 数据库与配置随系统备份（Bundle）恢复
- **智能滚动** — 分阶段跟随（思考即时钉底、正文平滑动画），手动滚动暂停，悬浮「回到底部」按钮
- **Markdown 渲染** — 原生渲染 + 懒加载 / 线程渲染性能优化 + 深色模式适配
- **文本交互** — 长按选中复制、代码块复制按钮、原文查看、AI 消息复制自动去除 Markdown 标记

## 快速开始

### 1. 运行项目

使用 DevEco Studio 打开项目根目录，等待依赖同步后连接真机或模拟器，点击 Run 即可。

### 2. 配置 API

应用内进入"设置"页填写（无需改代码，保存后持久化）：

| 字段     | 说明                                                      |
| -------- | --------------------------------------------------------- |
| 供应商   | 下拉选择，默认 DeepSeek（预设在 ModelPresets 注册表维护） |
| API Key  | 大模型密钥（密码输入框，加密存储）                        |
| 模型名称 | 当前供应商可选的模型下拉，空则使用供应商默认模型          |

- 接口地址 / 模型 / 能力开关由代码内预设（`ModelPresets.ets`）推导，设置页只读展示
- 联网搜索由 DeepSeek 服务端提供，无需单独配置搜索 Key
- ⚠️ 未配置时聊天前会拦截提示，引导前往设置页

## 项目结构

```
ChatCategorize/
├── AppScope/                 # 应用级配置（应用图标、app.json5）
├── entry/src/main/
│   ├── ets/
│   │   ├── common/           # 全局常量与公共工具
│   │   ├── config/           # 应用配置（Preferences + Asset Store 读写）
│   │   ├── database/         # 数据持久化层（DAO + Repository 分层）
│   │   ├── service/          # 服务层（Provider 工厂模式 + StreamTask）
│   │   ├── viewmodel/        # 状态管理层（MVVM 的 VM）
│   │   ├── model/            # 数据模型（@Observed 可观察对象）
│   │   ├── components/       # UI 组件（chat / item / dialog）
│   │   ├── pages/            # 页面（Home / Chat / SideBar / Folder / Settings）
│   │   ├── entryability/     # Ability 入口
│   │   └── entrybackupability/ # 备份恢复能力
│   ├── resources/            # 资源文件（string / color / float / media / profile）
│   └── module.json5          # 模块配置（INTERNET / KEEP_BACKGROUND_RUNNING 权限）
├── build-profile.json5       # 构建配置（本地签名，不入库）
├── oh-package.json5          # 根依赖管理
└── hvigorfile.ts             # 构建脚本
```

## 核心设计

### 1. 配置与密钥安全

- `AppConfig` 由 `EntryAbility.onCreate` 幂等预加载，`isConfigured()` 校验配置齐全
- 非敏感项（baseUrl / model）走 Preferences 明文存储
- 敏感项（API Key）走 SecureKeyStore 加密存储：Asset Store Kit（TEE）+ AES256-GCM，`SyncType.NEVER` 不参与云同步
- 旧版本明文 Key 自动迁入并删除明文残留，不硬编码任何密钥

### 2. LLM Provider — 工厂模式

- `LLMProvider` 抽象接口 + `DeepSeekProvider` 实现（Responses API，HTTP SSE 流式）
- `LLMProviderFactory` 按 `providerId` 分发，新增供应商只需在 ModelPresets 追加预设
- 请求体：`input` 消息列表 + `reasoning.effort`（思考强度，关闭 / Low / High / Max 四档由输入区下拉选择，关闭时显式传 `none`）+ `tools.web_search`（联网搜索）
- **统一错误模型**（`LLMError`）：各供应商错误归一化为统一 `ErrorCode` + 分类，`retryable` 决定是否保留续写；文案按码解析，序列化入库，重启后错误卡片可复现
- **输出截断**：`response.incomplete`（达 `max_output_tokens`）保留内容进入可续写态

### 3. 联网搜索

- 由 DeepSeek 服务端 `web_search` 工具执行，本地不调用第三方搜索 API
- 解析 `output_item.done` 的 `web_search_call`：搜索词（`search` 动作）与浏览网页（`open_page` 动作）
- 搜索过程以「【搜索】/【浏览】」前缀写入思考序列，按真实时序穿插展示
- 浏览记录结构化持久化（`searched_webs` 列），「x 个网页」面板点击可调系统浏览器
- 空回答（`EMPTY_ANSWER`）自动重试，超限落回暂停态

### 4. 数据库 — DAO + Repository 分层

基于 `relationalStore`，三张表：

| 表             | 说明                              |
| -------------- | --------------------------------- |
| `conversation` | 对话表                            |
| `message`      | 消息表（含思考 / 搜索记录 / 思考耗时 / 生成状态 / 错误 / 分支字段）    |
| `category`     | 文件夹 / 分类表（多级嵌套）       |

- `*Dao` 平铺单表 CRUD，`*Repository` 跨表聚合与事务
- 单例模式，`init()` 幂等建表；旧库通过 ALTER TABLE 幂等补列
- 删除对话级联删除消息；删空对话内全部消息时对话一并删除（单事务）；删除文件夹递归移除分类关系（对话保留）

### 5. 状态管理 — MVVM

- `ChatViewModel`：消息流、流式回调、智能滚动、对话分支
- `FolderViewModel`：文件夹树构建、多级导航、CRUD、多选批量操作（删除 / 取消收藏 / 移动）
- `SideBarViewModel`：历史会话分组、收藏、批量选择
- `SearchViewModel`：全局搜索（标题内存匹配 + 消息正文 DB 防抖查询、分支范围切换、命中消息定位）
- 页面与数据层解耦，ViewModel 桥接 DAO / Repository 与 ArkUI 状态

### 6. StreamTask — 多对话并发流式

- 一个流式任务 = 一个 `StreamTask`（缓冲 / 节流 / 占位消息）
- `Map<messageId, StreamTask>` 按消息粒度隔离，多对话 / 多分支可并发流式，缓冲互不串写
- AI 首次输出自动更新 `updatedAt` 置顶对话
- 异步操作带「过期结果守卫」，页面销毁清理定时器

### 7. 对话分支 — 分支链模型

每条消息记录 `parentId`、`branchGroupId`（= parentId）、`variantIndex`、`isActive`：

```
U1(root) ── A1 (variant 0) ── U2 ── A2          ← 激活链（高亮）
   │           └ A1' (variant 1)                  ← 同组变体（熄灭，可切回）
```

- 换个回答覆盖当前回复；生成新回复保留旧回复生成新变体
- 切换分支纯浏览不写库（`persist=false`），不改变历史落点
- 编辑后原位创建新分支；删除级联清理子树及对应流任务
- `allMessages` 缓存全量消息（含非激活变体），为分支操作的唯真源

### 8. 渲染与滚动优化

- **LazyForEach** 懒加载 + 30ms 流式节流；`cachedCount` 预加载 + 保持可见内容位置稳定，缓解快速滑动 / 流式增高的视口跳动
- **智能滚动**：思考阶段即时钉底、正文阶段 50ms 防抖 + 200ms 平滑动画；`scrollEdge` 优先定位；加载后多次钉底重试；变体切换用「锚点记录 + 增量替换 + 高度差补偿」防闪跳；用户滚动手势（拖动 / 惯性滑动 / 滚动条）期间暂停流式 UI 写入，到达底部时区分用户手势与代码滚动
- **Markdown 性能**：屏幕外块懒渲染 + 线程渲染 + 代码块折叠，库预热消除首开卡顿
- **思考过程块化渲染** — 思考段落聚合为块、搜索 / 浏览活动独立成块，流式增量复用块实例（@Trace 原地刷新），避免逐行重建抖动
- 消息高度变化即时钉底（流式与锚点恢复期间跳过）

### 9. 后台保活

- 后台有流式任务时申请 `dataTransfer` 长时任务（`backgroundTaskManager.startBackgroundRunning`），防止 SSE 连接被系统冻结
- 仅统计 `isStreaming=true` 的任务；全部结束或回前台立即释放
- 前置：`KEEP_BACKGROUND_RUNNING` 权限 + `backgroundModes: ["dataTransfer"]`

## 数据模型

| 模型           | 说明                                                                                     |
| -------------- | ---------------------------------------------------------------------------------------- |
| `Message`      | 单条消息（@Observed），含 reasoning / isThinking / isSearching 等状态；分支字段 parentId / branchGroupId / variantIndex / isActive |
| `Conversation` | 一个对话会话，可归属于某个 Category（文件夹）                                            |
| `Category`     | 文件夹 / 分类（@Observed），含 parentId（多级嵌套）与 color（图标颜色）                  |

## 权限说明

| 权限                              | 用途                         |
| --------------------------------- | ---------------------------- |
| `ohos.permission.INTERNET`        | 发起 LLM 请求（联网搜索由服务端执行）     |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | 后台保持流式连接不被冻结 |
