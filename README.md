# Harmony LLM Chat Categorize

> **简体中文 | [English](README_EN.md)**

基于 HarmonyOS NEXT 的 AI 聊天应用，支持 SSE 流式对话、深度思考、联网搜索、历史会话持久化与多级文件夹分类管理，采用 MVVM + 分层架构，使用 ArkTS / ArkUI 声明式开发。

## 技术栈

| 维度       | 选型                                                        |
| ---------- | ----------------------------------------------------------- |
| 平台       | HarmonyOS NEXT（API 20）                                    |
| 语言 / UI  | ArkTS / ArkUI 声明式（@Observed 状态管理，LazyForEach）     |
| 数据持久化 | relationalStore + Preferences                               |
| 凭据安全   | Asset Store Kit（TEE 加密存储 API Key）                     |
| 网络       | NetworkKit（HTTP SSE 流式，Responses API）                  |
| 大模型 API | DeepSeek Responses API（Provider 工厂模式可扩展）           |
| 联网搜索   | DeepSeek 服务端 web_search 工具                             |
| Markdown   | @luvi/lv-markdown-in 原生渲染（LaTeX / 代码高亮 / Mermaid） |

## 功能特性

- **流式对话** — SSE 逐字输出，思考内容与正文分通道展示
- **思考强度** — 关闭 / Low / High / Max 四档可调
- **联网搜索** — 搜索词与浏览网页实时可视化，可跳转
- **暂停 / 继续生成** — 中止保留内容，一键续写，重启可恢复
- **对话分支** — 换个回答 / 生成新回复 / 分支切换，旧分支可切回
- **消息编辑 / 删除** — 编辑原位生成新分支，删除级联清理
- **文件夹分类** — 无限层级，对话多选批量操作（删除 / 取消收藏 / 移动）
- **历史会话** — 自动持久化，按时间分组，全局搜索 / 多选 / 批量删除
- **全局搜索** — 标题 + 消息正文匹配，按对话分组，可定位到命中消息
- **密钥安全** — API Key 经 TEE 加密落盘，旧明文自动迁移
- **后台保活** — 后台流式时申请长时任务
- **沉浸式界面** — 全屏 edge-to-edge，系统栏与页面融合
- **智能滚动** — 生成中自动钉底，手动滚动暂停，回到底部按钮
- **Markdown 渲染** — 原生渲染 + 性能优化 + 深色模式
- **文本交互** — 长按复制、代码块复制、原文查看

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
├── AppScope/                  # 应用级配置
├── entry/src/main/
│   ├── ets/
│   │   ├── common/            # 常量与公共工具
│   │   ├── config/            # 应用配置与密钥存储
│   │   ├── database/          # 数据层（DAO + Repository）
│   │   ├── service/           # 服务层（Provider 工厂 + StreamTask）
│   │   ├── viewmodel/         # 状态层（MVVM）
│   │   ├── model/             # 数据模型
│   │   ├── components/        # UI 组件（chat / common / dialog / item / panel）
│   │   ├── pages/             # 页面
│   │   ├── entryability/      # Ability 入口
│   │   └── entrybackupability/# 备份恢复
│   ├── resources/             # 资源文件
│   └── module.json5           # 模块配置与权限
├── build-profile.json5        # 构建配置（本地签名，不入库）
├── oh-package.json5           # 依赖管理
└── hvigorfile.ts              # 构建脚本
```

## 核心设计

### 1. 配置与密钥安全
- 非敏感项（baseUrl / model）Preferences 明文存储；API Key 经 Asset Store Kit（TEE + AES256-GCM）加密存储，不参与云同步
- 旧版明文 Key 自动迁移并删除残留，不硬编码密钥

### 2. LLM Provider — 工厂模式
- `LLMProvider` 抽象接口 + `DeepSeekProvider` 实现（Responses API，SSE 流式）；工厂按 providerId 分发，新增供应商只需追加预设
- 请求携带 `reasoning.effort`（思考强度）与 `tools.web_search`（联网搜索）；统一错误模型，`response.incomplete` 进入可续写态

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

### 9. 后台保活
- 后台有流式任务时申请 `dataTransfer` 长时任务，全部结束或回前台立即释放（需 `KEEP_BACKGROUND_RUNNING` 权限）

### 10. 沉浸式系统栏
- 全屏布局 + 透明系统栏，深浅色动态适配；系统栏高度注入 AppStorage，页面显式避让（固定高度组件上 `safeAreaPadding` 会失效）

## 数据模型

| 模型           | 说明                                                       |
| -------------- | ---------------------------------------------------------- |
| `Message`      | 单条消息（@Observed），含思考 / 搜索 / 生成状态与分支字段 |
| `Conversation` | 一个对话会话，可归属某个文件夹                              |
| `Category`     | 文件夹 / 分类（@Observed），多级嵌套 + 图标颜色             |

## 权限说明

| 权限                                       | 用途                       |
| ------------------------------------------ | -------------------------- |
| `ohos.permission.INTERNET`                 | 发起 LLM 请求              |
| `ohos.permission.KEEP_BACKGROUND_RUNNING`  | 后台保持流式连接不被冻结   |
