# Harmony LLM Chat Categorize

基于 HarmonyOS NEXT 的 AI 聊天应用，支持流式对话、对话分类管理。

## 技术栈

- **平台**: HarmonyOS NEXT (API 20 / 6.0.0)
- **语言**: ArkTS (TypeScript 严格模式)
- **UI 框架**: ArkUI 声明式开发
- **网络**: `@kit.NetworkKit` (HTTP SSE 流式请求)
- **AI API**: OpenAI 兼容接口（默认使用 DeepSeek）

## 功能特性

- 流式 AI 对话 — SSE 逐字输出
- 聊天气泡 — 用户/AI 双色区分
- 智能时间分割线 — 超过 10 分钟自动显示
- 对话分类管理（Category）
- 多轮对话上下文支持
- 键盘避让模式（RESIZE）

## 项目结构

```
ChatCategorize/
├── entry/src/main/
│   ├── ets/
│   │   ├── common/          # 全局常量（颜色、字号、间距）
│   │   │   └── AppConstants.ets
│   │   ├── config/          # 应用配置（API Key、模型）
│   │   │   └── AppConfig.ets
│   │   ├── service/         # AI 对话服务（SSE 流式请求）
│   │   │   └── AIService.ets
│   │   ├── model/           # 数据模型
│   │   │   ├── Message.ets        # 消息模型
│   │   │   ├── Conversation.ets   # 对话模型
│   │   │   └── Category.ets       # 分类模型
│   │   ├── components/      # UI 组件
│   │   │   ├── MessageBubble.ets  # 聊天气泡
│   │   │   └── ChatInput.ets      # 底部输入栏
│   │   ├── pages/           # 页面
│   │   │   ├── ChatPage.ets       # 主聊天页
│   │   │   └── SideBar.ets        # 侧边栏
│   │   └── entryability/    # Ability 入口
│   │       └── EntryAbility.ets
│   └── module.json5         # 模块配置（含 INTERNET 权限）
├── build-profile.json5      # 构建配置
└── oh-package.json5         # 依赖管理
```

## 快速开始

### 1. 配置 API Key

打开 `entry/src/main/ets/config/AppConfig.ets`，替换你的 API Key：

```typescript
private config: ApiConfig = {
  baseUrl: "https://api.deepseek.com/chat/completions",
  apiKey: "你的API-Key",   // ← 替换这里
  model: "deepseek-v4-flash",
};
```

默认使用 DeepSeek，也支持任何 OpenAI 兼容 API（如 OpenAI、通义千问等）。

### 2. 运行项目

使用 DevEco Studio 打开项目，连接设备或模拟器后点击运行。

## 核心设计

### AIService — SSE 流式对话

```
用户输入 → ChatPage 创建占位消息 → AIService.sendMessage()
  → HTTP POST (stream: true)
  → dataReceive 逐 chunk 解析 SSE
  → onChunk 回调逐字更新 UI
  → dataEnd / [DONE] 标记完成
```

- 单例模式，全局唯一实例
- SSE 不完整 chunk 缓冲处理
- 防止重复回调（isFinished 标记）
- 连接超时 15s，读取超时 60s

### AppConfig — 配置管理

当前为硬编码阶段，后续将替换为 `@ohos.data.preferences` 持久化存储。

### 数据模型

| 模型             | 说明                                             |
| ---------------- | ------------------------------------------------ |
| `Message`      | 单条消息（@Observed 可观察，用于 UI 响应式更新） |
| `Conversation` | 一个对话会话，可归属于某个 Category              |
| `Category`     | 对话分类，支持侧边栏筛选                         |
