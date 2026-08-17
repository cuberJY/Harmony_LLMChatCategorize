# Harmony LLM Chat Categorize

> **English | [简体中文](README.md)**

An AI chat app for HarmonyOS NEXT with SSE streaming chat, deep thinking, web search, persistent history and multi-level folder categorization, built with an MVVM + layered architecture using ArkTS / ArkUI declarative development.

## Tech Stack

| Dimension         | Choice                                                               |
| ----------------- | -------------------------------------------------------------------- |
| Platform          | HarmonyOS NEXT 6.0.0 (API 20, targetSdkVersion / compatibleSdkVersion) |
| Language          | ArkTS (strongly typed + declarative)                                 |
| UI framework      | ArkUI declarative development (@State / @Observed state, LazyForEach) |
| Persistence       | `@kit.ArkData` relationalStore + Preferences                         |
| Credential safety | `@kit.AssetStoreKit` encrypted API Key storage (AES256-GCM, key in TEE) |
| Network           | `@kit.NetworkKit` (HTTP SSE streaming, Responses API)                |
| LLM API           | DeepSeek Responses API (provider preset registry + factory pattern)  |
| Web search        | DeepSeek server-side web_search tool (no local third-party search)   |
| Markdown          | `@luvi/lv-markdown-in` native rendering (LaTeX, code highlight, Mermaid) |

## Features

- **Streaming chat** — SSE token-by-token output; thinking and main text in separate channels
- **Thinking effort** — four-level dropdown (Off / Low / High / Max) in the input bar, via Responses API `reasoning.effort`
- **Web search** — server-side `web_search` tool; search terms and browsed pages visualized in real time, with an "x pages" list
- **Pause / resume** — abort mid-generation while keeping content; auto-pause on network errors; resume unfinished generation after restart
- **Structured errors** — error card shows category + copy + expandable detail, keeping the body clean
- **Conversation branches** — change answer / generate new reply / switch branch; old branches kept in the DB
- **Edit / delete messages** — editing creates a new branch in place; deletion cascades
- **Folder categorization** — unlimited depth; create / rename / move / delete; archive conversations; multi-select batch operations inside a folder (unfavorite / delete / move to another folder)
- **History** — auto-persisted, time-grouped sidebar, global search / multi-select / batch delete
- **Global search** — a search sheet opens from the sidebar's magnifier icon; matches conversation titles and message content, groups hits by conversation with snippets, and jumps precisely to the matching message; scope can be limited to active branches or include all historical branches
- **Secure key storage** — API Key encrypted via Asset Store Kit (TEE); legacy plaintext auto-migrated
- **Background keep-alive** — requests a `dataTransfer` continuous task while streaming in background
- **Immersive UI** — full-screen edge-to-edge layout; transparent system bars blend into the page and content is never obscured; cleaner dark-mode palette
- **System backup / restore** — DB and config restored with system backup (Bundle)
- **Smart scroll** — staged follow (instant pin while thinking, smooth animation for main text), pause on manual scroll, "back to bottom" floating button
- **Markdown rendering** — native rendering + lazy/threaded rendering optimizations + dark-mode support
- **Text interaction** — long-press select/copy, code-block copy button, raw-text viewer, plain-text copy of AI messages (Markdown stripped)

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
├── AppScope/                 # App-level config (icon, app.json5)
├── entry/src/main/
│   ├── ets/
│   │   ├── common/           # Global constants & utilities
│   │   ├── config/           # App config (Preferences + Asset Store)
│   │   ├── database/         # Persistence layer (DAO + Repository)
│   │   ├── service/          # Service layer (Provider factory + StreamTask)
│   │   ├── viewmodel/        # State layer (MVVM ViewModels)
│   │   ├── model/            # Data models (@Observed)
│   │   ├── components/       # UI components (chat / common / dialog / item / panel; common = reusable multi-select edit title/action bars)
│   │   ├── pages/            # Pages (Home / Chat / SideBar / Folder / Settings)
│   │   ├── entryability/     # Ability entry
│   │   └── entrybackupability/ # Backup & restore capability
│   ├── resources/            # Resources (string / color / float / media / profile)
│   └── module.json5          # Module config (INTERNET / KEEP_BACKGROUND_RUNNING)
├── build-profile.json5       # Build config (local signing, not committed)
├── oh-package.json5          # Root dependency management
└── hvigorfile.ts             # Build script
```

## Core Design

### 1. Config & Key Security

- `AppConfig` is idempotently preloaded in `EntryAbility.onCreate`; `isConfigured()` validates readiness
- Non-sensitive items (baseUrl / model) use Preferences plaintext storage
- Sensitive items (API Key) use SecureKeyStore: Asset Store Kit (TEE) + AES256-GCM, `SyncType.NEVER` to skip cloud sync
- Legacy plaintext keys auto-migrate and are purged; no hardcoded secrets

### 2. LLM Provider — Factory Pattern

- `LLMProvider` abstract interface + `DeepSeekProvider` implementation (Responses API, HTTP SSE streaming)
- `LLMProviderFactory` dispatches by `providerId`; adding a provider only needs a ModelPresets preset
- Request body: `input` message list + `reasoning.effort` (thinking strength, four levels Off / Low / High / Max chosen from the input-bar dropdown; `none` is sent explicitly to disable thinking) + `tools.web_search`
- **Unified error model** (`LLMError`): vendor errors normalized into a unified `ErrorCode` + category; `retryable` decides whether resume is kept; copy resolved by code and persisted, so error cards survive restarts
- **Output truncation**: `response.incomplete` (hit `max_output_tokens`) keeps content and enters the resumable state

### 3. Web Search

- Executed by DeepSeek's server-side `web_search` tool; no local third-party search API
- Parses `web_search_call` in `output_item.done`: search terms (`search`) and browsed pages (`open_page`)
- Search progress is written into the thinking sequence with `【搜索】/【浏览】` prefixes, interleaved in real order
- Browsed pages persisted structurally (`searched_webs` column); the "x pages" sheet opens the system browser
- Empty answers (`EMPTY_ANSWER`) auto-retry, falling back to the paused state after the limit

### 4. Database — DAO + Repository Layers

Based on `relationalStore`, three tables:

| Table            | Description                              |
| ---------------- | ---------------------------------------- |
| `conversation`   | Conversation table                       |
| `message`        | Message table (thinking / search records / thinking duration / generation status / error / branch fields) |
| `category`       | Folder/category table (multi-level nesting) |

- `*Dao` for flat single-table CRUD, `*Repository` for cross-table aggregation and transactions
- Singleton; `init()` idempotently creates tables; legacy DBs get columns via idempotent ALTER TABLE
- Deleting a conversation cascades to messages; deleting all messages in a conversation removes the conversation too (single transaction); deleting a folder recursively removes category relations (conversations kept)

### 5. State Management — MVVM

- `ChatViewModel`: message flow, streaming callbacks, smart scroll, branching
- `FolderViewModel`: folder tree, multi-level navigation, CRUD, multi-select batch ops (delete / unfavorite / move)
- `SideBarViewModel`: history grouping, favorites, batch selection
- `SearchViewModel`: global search (in-memory title match + debounced DB content query, branch scope toggle, hit positioning)
- Pages decouple from data; ViewModels bridge DAO/Repository and ArkUI state

### 6. StreamTask — Concurrent Streaming

- One stream = one `StreamTask` (buffers / throttle / placeholder message)
- `Map<messageId, StreamTask>` isolates streams per message; multiple conversations / branches stream concurrently without cross-writes
- The AI's first output auto-refreshes `updatedAt` to pin the conversation
- Async operations use "stale result guards"; timers cleaned up on page destroy

### 7. Conversation Branches — Branch Chain Model

Each message records `parentId`, `branchGroupId` (= parentId), `variantIndex`, `isActive`:

```
U1(root) ── A1 (variant 0) ── U2 ── A2          ← active chain (highlighted)
   │           └ A1' (variant 1)                  ← sibling variant (dimmed, switchable)
```

- Change answer overwrites the current reply; generate new reply keeps the old reply and creates a new variant
- Switching branches is pure browsing without DB writes (`persist=false`), preserving the historical landing point
- Editing creates a new branch in place; deletion cascades the subtree and its stream tasks
- `allMessages` caches all messages (including inactive variants) as the single source of truth

### 8. Rendering & Scroll Optimizations

- **LazyForEach** lazy loading + 30ms streaming throttle; `cachedCount` preloading + stable visible-content position, easing viewport jumps on fast scroll / streaming height growth
- **Smart scroll**: instant pin while thinking, 50ms debounce + 200ms animation for main text; `scrollEdge`-first positioning; repeated pin-after-load retries; variant switching uses "anchor record + incremental replace + height compensation" to avoid flicker; streaming UI writes pause during any user scroll gesture (drag/fling/scroll-bar), and reaching the bottom distinguishes user gestures from programmatic scrolling
- **Markdown performance**: off-screen lazy rendering + threaded rendering + code-block collapse, with library preheating to remove first-open jank
- **Reasoning block rendering** — thinking paragraphs aggregated into blocks, search/browse activities as separate blocks; streaming increments reuse block instances (@Trace in-place refresh), avoiding per-line rebuild jitter
- Instant re-pin on item height change (skipped while streaming and during anchor restoration)

### 9. Background Keep-alive

- Requests a `dataTransfer` continuous task (`backgroundTaskManager.startBackgroundRunning`) while streaming in background to prevent the SSE connection from being frozen
- Only counts `isStreaming=true` tasks; released immediately when all finish or the app returns to foreground
- Prerequisites: `KEEP_BACKGROUND_RUNNING` permission + `backgroundModes: ["dataTransfer"]`

### 10. Immersive System-bar Adaptation

- `EntryAbility` enables full-screen layout (`setWindowLayoutFullScreen`) with transparent system bars whose content color switches dynamically with dark/light mode (`onConfigurationUpdate`)
- Status/navigation bar heights are read via `getWindowAvoidArea` into `AppStorage`; pages use `SafeAreaHelper` plus explicit padding to avoid the bars (since `safeAreaPadding` fails on fixed-height components); the multi-select edit title/action bars already include immersive adaptation

## Data Models

| Model           | Description                                                                                |
| --------------- | ------------------------------------------------------------------------------------------ |
| `Message`       | A single message (@Observed), with reasoning / isThinking / isSearching states; branch fields parentId / branchGroupId / variantIndex / isActive |
| `Conversation`  | A conversation, optionally owned by a Category (folder)                                     |
| `Category`      | Folder/category (@Observed), with parentId (nesting) and color (icon color)                 |

## Permissions

| Permission                              | Purpose                              |
| --------------------------------------- | ------------------------------------ |
| `ohos.permission.INTERNET`              | Make LLM requests (web search is server-side) |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | Keep the streaming connection alive in background |
