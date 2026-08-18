# Harmony LLM Chat Categorize

> **English | [简体中文](README.md)**

An AI chat app for HarmonyOS NEXT with SSE streaming chat, deep thinking, web search, persistent history and multi-level folder categorization, built with an MVVM + layered architecture using ArkTS / ArkUI declarative development.

## Tech Stack

| Dimension         | Choice                                                            |
| ----------------- | ----------------------------------------------------------------- |
| Platform          | HarmonyOS NEXT (API 20)                                           |
| Language / UI     | ArkTS / ArkUI declarative (@Observed state, LazyForEach)          |
| Persistence       | relationalStore + Preferences                                     |
| Credential safety | Asset Store Kit (API Key encrypted in TEE)                        |
| Network           | NetworkKit (HTTP SSE streaming, Responses API)                    |
| LLM API           | DeepSeek Responses API (extensible Provider factory)              |
| Web search        | DeepSeek server-side web_search tool                              |
| Markdown          | @luvi/lv-markdown-in native rendering (LaTeX / code highlight / Mermaid) |
| Share parsing     | marked ArkTS port ([Harmony-Markdown-Editor](https://github.com/electronicminer/Harmony-Markdown-Editor), MIT) |

## Features

- **Streaming chat** — SSE token-by-token output; thinking and main text in separate channels
- **Thinking effort** — four levels (Off / Low / High / Max)
- **Web search** — search terms and browsed pages visualized in real time, with jump support
- **Pause / resume** — abort mid-generation while keeping content; one-tap resume; recoverable after restart
- **Conversation branches** — change answer / generate new reply / switch branch; old branches switchable back
- **Edit / delete messages** — editing creates a new branch in place; deletion cascades
- **Folder categorization** — unlimited depth; multi-select batch ops (delete / unfavorite / move)
- **History** — auto-persisted, time-grouped, global search / multi-select / batch delete
- **Global search** — matches titles and message content, grouped by conversation, with hit positioning
- **Secure key storage** — API Key encrypted in TEE; legacy plaintext auto-migrated
- **Background keep-alive** — continuous task while streaming in background
- **Immersive UI** — full-screen edge-to-edge; system bars blend into the page
- **Smart scroll** — auto-pin while generating, pause on manual scroll, "back to bottom" button
- **Markdown rendering** — native rendering + performance optimizations + dark-mode support
- **Text interaction** — long-press copy, code-block copy, raw-text viewer
- **Share** — one-tap share of messages / conversations as plain text, HTML, image, or PDF; AI replies keep their rich formatting

## Quick Start

### 1. Run the project

Open the project root in DevEco Studio, wait for dependency sync, connect a device/emulator, and click Run.

### 2. Configure the API

Fill in the in-app "Settings" page (no code changes, persisted after save):

| Field     | Description                                               |
| --------- | --------------------------------------------------------- |
| Provider  | Dropdown, defaults to DeepSeek (presets in ModelPresets)  |
| API Key   | LLM secret (password input, encrypted storage)            |
| Model     | Dropdown of the provider's models; empty uses the default |

- Endpoint / models / capability flags are derived from code presets (`ModelPresets.ets`) and shown read-only
- Web search is provided by the DeepSeek server; no separate search key is needed
- ⚠️ Chat is blocked with a prompt to visit Settings until configured

## Project Structure

```
ChatCategorize/
├── AppScope/                  # App-level config
├── entry/src/main/
│   ├── ets/
│   │   ├── common/            # Constants & utilities (markdown/ = marked port core)
│   │   ├── config/            # App config & key storage
│   │   ├── database/          # Data layer (DAO + Repository)
│   │   ├── service/           # Service layer (Provider factory + StreamTask)
│   │   ├── viewmodel/         # State layer (MVVM)
│   │   ├── model/             # Data models
│   │   ├── components/        # UI components (chat / common / dialog / item / panel)
│   │   ├── pages/             # Pages
│   │   ├── entryability/      # Ability entry
│   │   └── entrybackupability/# Backup & restore
│   ├── resources/             # Resources
│   └── module.json5           # Module config & permissions
├── build-profile.json5        # Build config (local signing, not committed)
├── oh-package.json5           # Dependency management
└── hvigorfile.ts              # Build script
```

## Core Design

### 1. Config & Key Security
- Non-sensitive items (baseUrl / model) use Preferences plaintext storage; the API Key is encrypted via Asset Store Kit (TEE + AES256-GCM) and never cloud-synced
- Legacy plaintext keys auto-migrate and are purged; no hardcoded secrets

### 2. LLM Provider — Factory Pattern
- `LLMProvider` abstract interface + `DeepSeekProvider` implementation (Responses API, SSE streaming); the factory dispatches by providerId, and adding a provider only needs a preset
- Requests carry `reasoning.effort` (thinking strength) and `tools.web_search`; unified error model; `response.incomplete` enters the resumable state

### 3. Web Search
- Executed by the DeepSeek server; search terms and browsed pages are written into the thinking sequence in real time, browsed pages are persisted structurally, and the "x pages" sheet opens the system browser

### 4. Database — DAO + Repository
- relationalStore with three tables: `conversation` / `message` / `category`; DAOs for flat single-table CRUD, Repositories for cross-table aggregation and transactions
- Idempotent table/column creation; cascading deletes, conversation removal when emptied, folder deletion keeps conversations

### 5. State Management — MVVM
- `ChatViewModel`: message flow, smart scroll, branching; `FolderViewModel` / `SideBarViewModel` / `SearchViewModel`: folders, history, global search
- ViewModels bridge DAO/Repository and ArkUI state; pages decouple from data

### 6. Stream Tasks
- One StreamTask per message, isolated by message ID so multiple conversations / branches stream concurrently without cross-writes; stale-result guards and timer cleanup on page destroy

### 7. Conversation Branches — Branch Chain Model
- Each message records `parentId` / `branchGroupId` / `variantIndex` / `isActive`; change answer overwrites, generate new reply adds a variant, and switching branches is pure browsing without DB writes

### 8. Rendering & Scroll Optimizations
- LazyForEach lazy loading + streaming throttle + stable visible position; instant pin while thinking, smooth animation for main text, streaming UI writes paused during user scroll gestures
- Markdown lazy rendering + block-based reasoning rendering to avoid per-line rebuild jitter

### 9. Share Markdown Parsing — marked Port
- Introduced the **marked ArkTS port parsing core** from [Harmony-Markdown-Editor](https://github.com/electronicminer/Harmony-Markdown-Editor) (MIT), replacing the previous hand-written lightweight parser, used for sharing (HTML / PDF / plain text)
- Located at `entry/src/main/ets/common/markdown/`, full GFM: tables / strikethrough / nested lists / task lists etc.; code blocks get lightweight highlighting via `HighlightAnalyzer` (`<span class="hl-*">` + injected CSS)
- Unified wrapper in `service/MarkdownParser.ets` (`markdownToHtml` / `markdownToText` / `HIGHLIGHT_CSS`); HTML and PDF sharing share the same parser, so both formats benefit together
- The upstream `Markdown/src/main/ets/core/` is the ArkTS port of marked (github.com/markedjs/marked); this project extracts the pure parsing layer and adapts it to ArkTS strict mode (removed extensions / explicit types / Map-based links etc.)

### 10. Background Keep-alive
- Requests a `dataTransfer` continuous task while streaming in background, released when all finish or the app returns to foreground (needs `KEEP_BACKGROUND_RUNNING` permission)

### 11. Immersive System Bars
- Full-screen layout + transparent system bars with dark/light adaptation; bar heights injected into AppStorage and explicitly avoided by pages (since `safeAreaPadding` fails on fixed-height components)

## Data Models

| Model           | Description                                                        |
| --------------- | ------------------------------------------------------------------ |
| `Message`       | A single message (@Observed), with thinking / search / generation state and branch fields |
| `Conversation`  | A conversation, optionally owned by a folder                        |
| `Category`      | Folder/category (@Observed), multi-level nesting + icon color       |

## Permissions

| Permission                              | Purpose                            |
| --------------------------------------- | ---------------------------------- |
| `ohos.permission.INTERNET`              | Make LLM requests                  |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | Keep the streaming connection alive in background |
