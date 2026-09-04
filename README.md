# Harmony LLM Chat Categorize（端云一体化）

> **简体中文 | [English](README_EN.md)**

基于 HarmonyOS NEXT 的端云一体化 AI 聊天应用。客户端具备 SSE 流式对话、深度思考、联网搜索、多级文件夹分类等完整能力，并通过 AGC 云开发（Cloud DB + Cloud Functions + Auth）实现数据云同步。采用 MVVM + 分层架构，ArkTS / ArkUI 声明式开发。

## 技术栈

| 维度         | 选型                                                        |
| ------------ | ----------------------------------------------------------- |
| 平台         | HarmonyOS NEXT（API 24）                                    |
| 语言 / UI    | ArkTS / ArkUI 声明式（@Observed 状态管理，LazyForEach）     |
| 数据持久化   | relationalStore + Preferences                               |
| 凭据安全     | Asset Store Kit（TEE 加密存储 API Key）                     |
| 网络         | NetworkKit（HTTP SSE 流式，Responses API）                  |
| 大模型 API   | DeepSeek Responses API（Provider 工厂模式可扩展）           |
| 联网搜索     | DeepSeek 服务端 web_search 工具                             |
| Markdown     | @luvi/lv-markdown-in 原生渲染（LaTeX / 代码高亮 / Mermaid） |
| 分享解析     | marked ArkTS 移植（[Harmony-Markdown-Editor](https://github.com/electronicminer/Harmony-Markdown-Editor)，MIT） |
| 文档解析     | @ohos/jszip + 自研 OOXML 提取器（docx / pptx / xlsx → Markdown），ArkWeb + deck-ir / docx-preview（视觉模型下 docx/pptx 排版还原截图），PDF Kit（pdf 逐页渲染） |
| 云端同步     | AGC Cloud DB（Cloud Foundation Kit，本地 RDB 双向同步）     |
| 云认证       | AGC Auth（匿名登录）                                        |
| 云函数       | Cloud Functions（id-generator 生成 UUID）                   |

## 功能特性

- **流式对话** — SSE 逐字输出，思考内容与正文分通道展示
- **思考强度** — 关闭 / Low / High / Max 四档可调
- **联网搜索** — 搜索词与浏览网页实时可视化，可跳转
- **暂停 / 继续生成** — 中止保留内容，一键续写，重启可恢复
- **对话分支** — 换个回答 / 生成新回复 / 分支切换，旧分支可切回
- **消息编辑 / 删除** — 编辑原位生成新分支，删除级联清理
- **文件夹分类** — 无限层级，层级树选择器移动对话，对话多选批量操作（删除 / 取消收藏 / 移动）
- **历史会话** — 自动持久化，按时间分组，全局搜索 / 多选 / 批量删除；首轮问答完成后自动生成对话标题
- **全局搜索** — 标题 + 消息正文匹配，按对话分组，可定位到命中消息
- **密钥安全** — API Key 经 TEE 加密落盘，旧明文自动迁移
- **账号登录 / 云同步** — AGC Auth 匿名登录，本地数据与 AGC Cloud DB 全量双向同步（last-write-wins 合并）；「账号登录」页展示同步状态并支持手动立即同步
- **模型配置** — 独立二级页集中配置供应商 / 模型 / API Key
- **后台保活** — 后台流式时申请长时任务
- **沉浸式界面** — 全屏 edge-to-edge，系统栏与页面融合
- **多端适配** — 按宽度断点自适应手机 / 平板 / 折叠屏；宽屏侧边栏常驻分栏，折叠屏展开收起实时重排
- **智能滚动** — 生成中自动钉底，手动滚动暂停，回到底部按钮
- **Markdown 渲染** — 原生渲染 + 性能优化 + 深色模式
- **文本交互** — 长按复制、代码块复制、原文查看
- **图片输入** — 视觉模型下支持相册选图与拍照发送（自动压缩，最多 9 张），消息图片可全屏预览，编辑消息可增删图片
- **文件输入** — 支持发送 txt / md / pdf / docx / pptx / xlsx 附件，AI 自动提取内容理解（解析细节见核心设计）
- **分享** — 消息 / 对话一键分享：纯文本、Markdown、HTML、长图、PDF 五格式，AI 回复富文本原样呈现；长对话按轮分段导出为长图 / 多页 PDF

## 快速开始

### 1. 运行项目

使用 DevEco Studio 打开 `Application/` 目录，等待依赖同步后连接真机或模拟器，点击 Run 即可。

### 2. 配置 API

应用内进入"设置-模型配置"页填写（无需改代码，保存后持久化）：

| 字段     | 说明                                                      |
| -------- | --------------------------------------------------------- |
| 供应商   | 下拉选择，目前仅支持DeepSeek（预设在 ModelPresets 注册表维护） |
| API Key  | 大模型密钥（密码输入框，加密存储）                        |
| 模型名称 | 当前供应商可选的模型下拉，空则使用供应商默认模型          |

- 接口地址 / 模型 / 能力开关由代码内预设（`ModelPresets.ets`）推导，设置页只读展示
- 联网搜索由 DeepSeek 服务端提供

### 3. 部署云开发（CloudProgram）

云同步依赖 AGC 云开发，需先在 [AppGallery Connect](https://developer.huawei.com/consumer/cn/service/josp/agc/index.html) 完成以下配置：

1. 创建应用（bundleName 与客户端一致）并开通**认证服务**（允许匿名登录）与**云数据库**
2. 在云数据库按 `CloudProgram/clouddb/objecttype/` 下三类对象（conversation / message / category）创建 schema 并部署
3. 部署云函数 `id-generator`（生成 UUID）
4. 下载 `agconnect-services.json` 放入客户端 `Application/AppScope/resources/rawfile/`（不参与版本管理）
5. 运行应用，进入"设置-账号登录"页，点击「立即同步」完成认证初始化与首次同步

## 项目结构

```
ChatCategorize/
├── Application/                  # HarmonyOS 客户端（端云一体化）
│   ├── AppScope/                 # 应用级配置（含云数据库 schema.json、agconnect-services.json）
│   ├── entry/src/main/
│   │   ├── ets/
│   │   │   ├── common/           # 常量与公共工具（markdown/ 为 marked 移植核心；ChatBridge 跨页桥接、DeviceAdapt 多端适配）
│   │   │   ├── config/           # 应用配置与密钥存储
│   │   │   ├── database/         # 数据层（DAO + Repository）
│   │   │   ├── service/          # 服务层（Provider 工厂 + StreamTask + sync/ 云同步）
│   │   │   ├── viewmodel/        # 状态层（MVVM）
│   │   │   ├── model/            # 数据模型
│   │   │   ├── components/       # UI 组件（chat / common / dialog / item / panel）
│   │   │   ├── pages/            # 页面（含 AccountSyncPage、ModelConfigPage）
│   │   │   ├── entryability/     # Ability 入口
│   │   │   └── entrybackupability/# 备份恢复
│   │   ├── resources/            # 资源文件
│   │   └── module.json5          # 模块配置与权限
│   ├── cloud_objects/            # 客户端云数据库对象（Cloud Objects 编译器生成，调用云函数）
│   ├── build-profile.json5       # 构建配置（本地签名，不入库）
│   ├── oh-package.json5          # 依赖管理（@hw-agconnect/auth）
│   └── hvigorfile.ts             # 构建脚本
└── CloudProgram/                 # 云开发
    ├── clouddb/                  # 云数据库（objecttype: conversation / message / category）
    ├── cloudfunctions/           # 云函数（id-generator）
    ├── cloud-config.json         # AGC 项目配置
    └── package.json
```

## 核心设计

### 1. 配置与密钥安全
- 非敏感项（baseUrl / model）Preferences 明文存储；API Key 经 Asset Store Kit（TEE + AES256-GCM）加密存储，不参与云同步
- 旧版明文 Key 自动迁移并删除残留，不硬编码密钥

### 2. LLM Provider — 工厂模式
- `LLMProvider` 抽象接口 + `DeepSeekProvider` 实现（Responses API，SSE 流式）；工厂按 providerId 分发，新增供应商只需追加预设
- 请求携带 `reasoning.effort`（思考强度）与 `tools.web_search`（联网搜索）；视觉模型支持图片输入（`input_image` 内容块，Base64 内联）；统一错误模型，`response.incomplete` 进入可续写态

### 3. 联网搜索
- 由 DeepSeek 服务端执行；搜索词与浏览记录实时写入思考序列，浏览记录结构化持久化，「x 个网页」面板可调系统浏览器

### 4. 数据库 — DAO + Repository
- relationalStore 三张表：`conversation` / `message` / `category`；DAO 平铺单表 CRUD，Repository 跨表聚合与事务
- 幂等建表补列；删除级联、删空对话连带删除、删除文件夹保留对话

### 5. 状态管理 — MVVM
- `ChatViewModel`：消息流、智能滚动、分支；`FolderViewModel` / `SideBarViewModel` / `SearchViewModel`：文件夹、历史、全局搜索
- ViewModel 桥接 DAO / Repository 与 ArkUI 状态，页面与数据层解耦

### 6. 流式任务
- 每个消息一个 StreamTask，按消息粒度隔离，多对话 / 多分支并发互不串写；异步结果带过期守卫，页面销毁清理定时器

### 7. 对话分支 — 分支链模型
- 消息记录 `parentId` / `branchGroupId` / `variantIndex` / `isActive` 构成分支链；换个回答覆盖、生成新回复新增变体、切换分支纯浏览不写库

### 8. 渲染与滚动优化
- LazyForEach 懒加载 + 流式节流 + 可见位置稳定；思考即时钉底、正文平滑动画，用户滚动手势期间暂停流式写入
- Markdown 懒渲染 + 思考过程块化渲染，避免逐行重建抖动

### 9. 分享 Markdown 解析 — marked 移植
- 引入 [Harmony-Markdown-Editor](https://github.com/electronicminer/Harmony-Markdown-Editor)（MIT）中的 **marked ArkTS 移植解析核心**，替换原手写轻量解析，用于分享（HTML / PDF / 纯文本）
- 位于 `entry/src/main/ets/common/markdown/`，完整 GFM：表格 / 删除线 / 嵌套列表 / 任务列表等；代码块经 `HighlightAnalyzer` 轻量高亮（`<span class="hl-*">` + 注入 CSS）
- 统一封装 `service/MarkdownParser.ets`（`markdownToHtml` / `markdownToText` / `HIGHLIGHT_CSS`）；HTML 与 PDF 分享共用同一解析，两格式同步受益
- 原仓库 `Markdown/src/main/ets/core/` 为 marked（github.com/markedjs/marked）的 ArkTS 移植；本工程提取纯解析层并做 ArkTS 严格模式兼容改造（去扩展 / 显式类型 / Map 化 links 等）
- 图片 / PDF 采用分段导出：宿主页面隐藏层（ExportCardLayer）按问答轮次分段渲染并逐段截图，图片经 ImageMerger 纵向拼接为长图、PDF 由 PdfExporter 按 A4 页高切分铺多页（规避弹层内截图不可用与超长卡片渲染缓冲上限）

### 10. 后台保活
- 后台有流式任务时申请 `dataTransfer` 长时任务，全部结束或回前台立即释放（需 `KEEP_BACKGROUND_RUNNING` 权限）

### 11. 沉浸式系统栏
- 全屏布局 + 透明系统栏，深浅色动态适配；系统栏高度注入 AppStorage，页面显式避让（固定高度组件上 `safeAreaPadding` 会失效）

### 12. 文件附件解析 — FileParser
- `service/FileParser.ets` 单例封装系统文档选择器（DocumentViewPicker 免存储权限）与文件解析：txt/md 直接读取 UTF-8 文本（超长截断）；docx/pptx/xlsx 经 `service/OoxmlParser.ets`（@ohos/jszip 解包 + XmlPullParser 流式解析 OOXML XML）提取为 Markdown 文本（docx 段落 / 标题 / 表格、pptx 逐页文本、xlsx 逐工作表表格含 sharedStrings 还原）；docx/pptx 在视觉模型下改走 `service/OfficeHtmlParser.ets`（隐藏 ArkWeb + deck-ir/docx-preview 排版还原）逐页截图；pdf 因 API 20 无 `getTextContent`，经 PDF Kit 逐页渲染为 PixelMap → JPEG Base64（≤100 页，页面 Base64 总量 ≤12MB 保护请求体）
- 发送按通道分发（`DeepSeekProvider.buildApiContent`）：txt/md 与 Office 提取文本以「【文件 xx 内容】」标注拼入 `input_text` 文本块（所有模型可用）；docx/pptx（视觉模型）/ PDF 页面图逐页作为 `input_image` 视觉块（仅视觉模型，选择 / 发送 / 编辑 / Provider 四层兜底拦截）
- 约束与交互：单文件 ≤20MB；提取文本（txt/md/docx/pptx/xlsx）≤3 万字符截断；文件卡片展示在消息气泡内，编辑消息可增删文件

### 13. 多端 / 宽屏适配
- `common/DeviceAdapt.ets` 统一断点体系（sm <600vp / md <840vp / lg ≥840vp）与折叠屏状态监听，状态经 AppStorageV2 全局共享，断点变化任意页面自动刷新
- 宿主 `HomePage` 依据断点动态切换 Navigation Stack / Split：宽屏（≥600vp）侧边栏嵌入式常驻左栏 + 聊天右栏，可拖拽调宽（25%~75%）并带原生分割线；窄屏保持抽屉式
- 宽屏下嵌入式侧边栏选中对话经 `common/ChatBridge.ets`（AppStorageV2 全局响应式总线）回传：`selectionVersion` 驱动 ChatPage 消费加载，`sidebarRefreshVersion` / `currentConversationId` 驱动列表刷新与高亮；聊天内容列限宽 720vp 居中
- 监听 `display.foldStatusChange` 与 `window.windowSizeChange`，折叠屏展开 / 收起实时切换分栏 / 单栏

### 14. 端云同步 — CloudSyncService
- **方案 A（本地 RDB 为主 + 云端副本）**：本地 RDB 为唯一数据源，`service/sync/cloud/CloudSyncService.ets` 负责与 AGC Cloud DB 全量双向同步；`service/sync/SyncManager.ets` 为同步门面（状态码 + 监听广播），「账号登录」页（AccountSyncPage）展示状态并触发手动同步
- **同步流程**：先 push（本地 → 云端：conversation / message / category 全量 `upsert`）再 pull（云端 → 本地，逐条按时间戳合并）；初始化经 AGC Auth 匿名登录获取 Authenticated 身份并注入 `cloudCommon`
- **冲突策略**：last-write-wins — conversation 用 `updated_at`，message / category 用 `created_at`（云侧秒级时间戳 ×1000 转毫秒后与本地比较）；删除暂不同步（避免墓碑机制，后续增强）
- **时间戳处理**：本地毫秒 → 云侧秒（规避 Cloud DB Integer 32 位溢出，`Date.now()` 约 1.7e12 超限）
- **云函数 id-generator**：经客户端 `cloud_objects`（Cloud Objects 编译器生成 + `importObject` Proxy）调用 Cloud Functions 生成 UUID

## 数据模型

| 模型           | 说明                                                       |
| -------------- | ---------------------------------------------------------- |
| `Message`      | 单条消息（@Observed），含思考 / 搜索 / 生成状态、图片与文件附件、分支字段 |
| `Conversation` | 一个对话会话，可归属某个文件夹                              |
| `Category`     | 文件夹 / 分类（@Observed），多级嵌套 + 图标颜色             |

云端三张表（`conversation` / `message` / `category`）与本地结构镜像，字段与上述模型一一对应，仅时间戳以秒存储。

## 权限说明

| 权限                                       | 用途                       |
| ------------------------------------------ | -------------------------- |
| `ohos.permission.INTERNET`                 | 发起 LLM 请求              |
| `ohos.permission.KEEP_BACKGROUND_RUNNING`  | 后台保持流式连接不被冻结   |
