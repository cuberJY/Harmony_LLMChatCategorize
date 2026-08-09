# Harmony LLM Chat Categorize

> **[简体中文](README.md) | English**

An AI chat application built on HarmonyOS NEXT, featuring streaming conversations, deep thinking, web search, persistent chat history, and conversation categorization.

## Tech Stack

- **Platform**: HarmonyOS NEXT (API 20 / 6.0.0)
- **Language**: ArkTS
- **UI Framework**: ArkUI declarative development (LazyForEach lazy loading)
- **Data Persistence**: `@kit.ArkData` relationalStore relational database + Preferences config storage
- **Credential Security**: `@kit.AssetStoreKit` encrypted API Key storage (AES256-GCM, keys stored in TEE, no cloud sync)
- **Network**: `@kit.NetworkKit` (HTTP SSE streaming / Web Search API)
- **LLM API**: OpenAI-compatible interface (DeepSeek by default, extensible via Provider factory)
- **Search API**: Bocha AI Web Search API (direct domestic access, extensible via Provider factory)

## Features

- **Streaming AI Chat** — SSE token-by-token output; reasoning content (`reasoning_content`) and main text displayed in separate channels
- **Deep Thinking (toggleable)** — DeepSeek official thinking format (enabled/disabled); `reasoning_effort=max` when on, forced off when disabled (V4 thinks by default, so it must be controlled explicitly)
- **Web Search** — Bocha Web Search for real-time info; results used as reference material to drive answers, auto-fallback on failure
- **Settings Page** — Fill in API URL / Key / model in-app; persisted after save, survives restarts
- **Secure Key Storage** — API Keys stored in Asset Store Kit (TEE-encrypted on disk, never written in plaintext); legacy plaintext auto-migrated and purged
- **Multi-level Folder Categorization** — Unlimited folder depth; Favorites tab shows top-level folders with drill-down navigation
- **Folder Management** — Create / rename / move / delete (with confirmation + cascading category relation removal), 8 selectable icon colors
- **Conversation Archiving** — Move conversations into any folder or back to unclassified; browse by folder
- **Conversation History** — Conversations auto-persisted; sidebar groups by time (Today / Yesterday / 7 days / 30 days / Year-Month)
- **Conversation Management** — Search filter, long-press menu (multi-select/delete), batch delete, swipe right edge to open history page
- **Message Persistence** — User messages and AI replies (including thinking content) saved in real time; reloadable from history
- **Smart Scroll** — Auto-follows the latest message; pauses following when the user scrolls manually
- **Streaming Throttle** — Incremental text merged every 50ms, reducing high-frequency stream updates to ~20fps
- **Concurrent Multi-conversation Streaming** — Each conversation has an independent StreamTask; switching away keeps the original stream running in the background without cross-writes
- **Stream Interruption** — Interrupt/cancel an in-progress stream; timers cleaned up on page destroy to prevent leaks
- **Background Streaming Keep-alive** — Requests a `dataTransfer` continuous task when in background with active streams so the SSE connection isn't frozen by the system
- **Keyboard Avoidance** — RESIZE mode pins input to the bottom when the keyboard appears
- **Smart Time Divider** — Auto-shows a divider when message gaps exceed 10 minutes

## Project Structure

```
ChatCategorize/
├── entry/src/main/
│   ├── ets/
│   │   ├── common/          # Global constants & utilities
│   │   │   ├── AppConstants.ets    # Colors, font sizes, spacing, prompt texts
│   │   │   ├── Utils.ets           # Utilities (generateId / showToast / delete confirmation)
│   │   │   ├── TimeUtil.ets        # Time grouping & smart time formatting
│   │   │   ├── Logger.ets          # Unified logging wrapper
│   │   │   └── NavTransitionManager.ets  # Page navigation transition animations
│   │   ├── config/          # App configuration
│   │   │   ├── AppConfig.ets       # Config management (Preferences + Asset Store)
│   │   │   └── SecureKeyStore.ets  # Secure key storage (Asset Store Kit wrapper)
│   │   ├── database/        # Relational database (DAO + Repository layers)
│   │   │   ├── DatabaseHelper.ets          # Schema creation + shared RdbStore
│   │   │   ├── ConversationDao.ets         # Conversation table CRUD
│   │   │   ├── MessageDao.ets              # Message table CRUD
│   │   │   ├── CategoryDao.ets             # Folder table CRUD
│   │   │   ├── ConversationRepository.ets  # Conversation+message aggregation / transactions
│   │   │   └── CategoryRepository.ets      # Folder tree + cascading delete
│   │   ├── service/         # Service layer (Provider factory pattern)
│   │   │   ├── LLMProviderFactory.ets      # LLM Provider factory
│   │   │   ├── SearchProviderFactory.ets   # Search Provider factory
│   │   │   ├── StreamTask.ets              # Single streaming task (isolated buffer/throttle/placeholder)
│   │   │   ├── BackgroundRunGuardService.ets # Background keep-alive (streaming not frozen)
│   │   │   └── provider/
│   │   │       ├── LLMProvider.ets         # LLM abstract interface (SSE streaming)
│   │   │       ├── DeepSeekProvider.ets    # DeepSeek implementation (OpenAI-compatible)
│   │   │       ├── SearchProvider.ets      # Search abstract interface
│   │   │       └── BochaSearchProvider.ets # Bocha search implementation
│   │   ├── viewmodel/       # State management layer
│   │   │   ├── ChatViewModel.ets           # Chat state & message flow
│   │   │   ├── FolderViewModel.ets         # Folder tree state
│   │   │   └── SideBarViewModel.ets        # Sidebar history/favorites state
│   │   ├── model/           # Data models
│   │   │   ├── Message.ets        # Message model (with thinking/search states)
│   │   │   ├── Conversation.ets   # Conversation model
│   │   │   ├── Category.ets       # Folder/category model
│   │   │   ├── FolderParams.ets   # Folder navigation params
│   │   │   └── SideBarParams.ets  # Sidebar route params (highlight current conversation)
│   │   ├── components/      # UI components (grouped by responsibility)
│   │   │   ├── chat/               # Chat-related
│   │   │   │   ├── MessageBubble.ets   # Chat bubble (with thinking block)
│   │   │   │   └── ChatInput.ets       # Input bar (deep thinking / web search toggles)
│   │   │   ├── item/                # List items
│   │   │   │   ├── ConversationItem.ets  # History conversation list item (long-press menu)
│   │   │   │   └── FolderItem.ets        # Folder list item (colored icon)
│   │   │   └── dialog/              # Dialogs
│   │   │       ├── RenameInputDialog.ets  # Generic text input dialog
│   │   │       ├── EditFolderDialog.ets   # Edit folder dialog
│   │   │       └── FolderPickerDialog.ets # Folder picker
│   │   ├── pages/           # Pages
│   │   │   ├── HomePage.ets       # Home page (navigation entry)
│   │   │   ├── ChatPage.ets       # Main chat page
│   │   │   ├── SideBarPage.ets    # Sidebar (Favorites / History tabs)
│   │   │   ├── FolderPage.ets     # Folder page (subfolders + conversations, multi-level)
│   │   │   └── SettingsPage.ets   # Settings page (API config form)
│   │   ├── entryability/    # Ability entry
│   │   │   └── EntryAbility.ets   # Preloads config in onCreate
│   │   └── entrybackupability/    # Backup & restore capability
│   │       └── EntryBackupAbility.ets
│   └── module.json5         # Module config (includes INTERNET permission)
├── build-profile.json5      # Build config (local signing, not committed)
└── oh-package.json5         # Dependency management
```

## Quick Start

### 1. Run the Project

Open the project with DevEco Studio, connect a device or emulator, and click Run.

### 2. Configure the API

Fill in the in-app **Settings** page (no code changes needed; persisted after saving):

| Field            | Description                                                                 |
| ---------------- | --------------------------------------------------------------------------- |
| API URL          | LLM endpoint, default `https://api.deepseek.com/chat/completions`, OpenAI-compatible |
| API Key          | LLM secret key (password input)                                             |
| Model Name       | e.g. `deepseek-v4-flash`                                                  |
| Search API URL   | Search endpoint, default `https://api.bochaai.com/v1/web-search`            |
| Search API Key   | Bocha key; leave empty to disable web search                               |

- The LLM defaults to DeepSeek and supports any OpenAI-compatible API
- Web search is powered by Bocha AI ([open.bochaai.com](https://open.bochaai.com) to register for a Key), free with direct domestic access
- ⚠️ When unconfigured, AppConfig fields are empty and you'll be prompted to visit the Settings page before chatting

## Core Design

### AppConfig — Config Management (Preferences + Asset Store)

- Idempotently preloaded by `AppConfig.getInstance().init(context)` in `EntryAbility.onCreate`
- **Non-sensitive fields** (baseUrl / model / searchBaseUrl) → stored in plaintext Preferences
- **Sensitive fields** (apiKey / searchApiKey) → encrypted in SecureKeyStore, never written in plaintext
- Legacy migration: detects plaintext Keys left in Preferences, auto-migrates them to Asset Store, then deletes the plaintext residue
- `isConfigured()` validates the three required LLM fields and blocks chatting with a prompt when unconfigured
- Defaults to empty strings; **no keys hardcoded**

### SecureKeyStore — Secure Key Storage

- Built on Asset Store Kit (analogous to iOS Keychain / Android Keystore); keys stored in the hardware secure area (TEE)
- AES256-GCM ciphertext on disk; plaintext can't be recovered even if app data is read or backed up
- `SyncType.NEVER`: excluded from cloud sync / cloud backup to prevent key leakage
- Provides `save` / `get` / `remove` static methods; saving an empty string clears the old key

### LLM Provider — SSE Streaming Chat (Factory Pattern)

```
User input → ChatViewModel → LLMProviderFactory.create()
  → DeepSeekProvider.sendMessage() (HTTP POST, stream: true)
  → dataReceive parses SSE chunk by chunk
  → onReasoningChunk outputs thinking content (reasoning_content)
  → onChunk outputs main text
  → dataEnd / [DONE] marks completion
```

- `LLMProvider` defines the abstract interface (streaming callbacks); `DeepSeekProvider` implements the OpenAI-compatible calls
- `LLMProviderFactory` creates Providers by channel; adding a model only requires implementing the interface and registering with the factory
- Buffers incomplete SSE chunks; prevents duplicate callbacks (isFinished flag)
- Connect timeout 15s, read timeout 60s
- Deep thinking uses DeepSeek's official format: `thinking.enabled/disabled` + `reasoning_effort=max`; the `deepThinking` toggle is passed from ChatInput, explicitly disabled when off (V4 thinks by default, so it must be controlled explicitly)

### Search Provider — Web Search (Factory Pattern)

```
Web search on → ChatViewModel → SearchProviderFactory.create()
  → BochaSearchProvider.search() (Bocha Web Search API POST)
  → Parses title/URL/long summary → builds LLM-friendly Markdown
  → Injected as a system message to drive LLM answers grounded in the material
```

- `SearchProvider` defines the abstract interface; `BochaSearchProvider` implements Bocha calls, fully decoupled from the LLM
- Returns 5 results, each summary truncated to 800 chars to control tokens
- On failure, silently falls back to a normal conversation; UI shows a degradation hint

### DatabaseHelper — Relational Database (DAO + Repository Layers)

Based on `relationalStore`, three tables:

| Table          | Fields                                                        | Description                                   |
| -------------- | -------------------------------------------------------------- | --------------------------------------------- |
| `conversation` | id, title, category_id, created_at, updated_at                 | Conversation table                            |
| `message`      | id, conversation_id, role, content, reasoning, created_at      | Message table (includes thinking content)     |
| `category`     | id, name, parent_id, color, sort_order, created_at             | Folder/category table (multi-level nesting)   |

- Layered design: `*Dao` for flat single-table CRUD (errors propagate up); `*Repository` for cross-table aggregation and transactions (folder tree, cascading delete)
- Singleton pattern; `init()` idempotently creates tables (IF NOT EXISTS)
- High-frequency query indexes: `message(conversation_id)`, `conversation(updated_at DESC)`
- Delayed conversation insertion: a record is created only on the first user message, avoiding empty conversations polluting history
- Deleting a conversation cascades message deletion (IN condition)
- Folder tree: empty `parent_id` means top-level; `getCategorySubtreeIds()` collects descendant nodes; moving a folder excludes itself to prevent cycles
- Cascading folder delete: `deleteCategoryCascade()` recursively collects descendants, then removes their category relations (conversations themselves are kept)
- All API calls wrapped in try-catch, silently degrading on exceptions

### ViewModel — State Management Layer

- `ChatViewModel`: chat message flow, streaming-callback-driven UI updates, smart scroll state
- `FolderViewModel`: folder tree construction, multi-level navigation, folder CRUD state
- `SideBarViewModel`: history grouping, Favorites tab, multi-select state
- Decouples pages from the data layer; ViewModels bridge DAO/Repository and ArkUI state

### StreamTask — Concurrent Multi-conversation Streaming

- One in-progress stream = one `StreamTask` instance (owning text/thinking buffers, throttle timer, AI placeholder message)
- `ChatViewModel` holds `Map<conversationId, StreamTask>`: switching to conversation B keeps A's stream progressing in the background with no buffer cross-writes
- Send limiting is per-conversation (`isStreamingFor`); streams in different conversations don't affect each other
- Async operations (loading conversations / fetching titles) use "stale result guards": re-validating the conversation id after `await` to prevent UI confusion from rapid switching
- On page destroy, all tasks are `clearTimer()`'d to prevent lingering timers from firing stale writes

### BackgroundRunGuardService — Background Streaming Keep-alive

- Background: the system freezes network resources ~2s after an app goes to background and releases them ~12s later, cutting off SSE streaming connections
- Solution: while in background **and** streams are active, request a `dataTransfer` continuous task (`backgroundTaskManager.startBackgroundRunning`) to keep the network connection alive
- Immediately calls `stopBackgroundRunning` when all tasks finish or the app returns to foreground, avoiding resource usage
- Prerequisites: `ohos.permission.KEEP_BACKGROUND_RUNNING` permission + `backgroundModes: ["dataTransfer"]` in EntryAbility
- ChatViewModel syncs the task count via `updateStreamingTaskCount`; EntryAbility's onForeground/onBackground switches the background state

### ChatPage — Rendering Optimizations

- **LazyForEach** (option C): custom `IDataSource` for lazy loading, rendering only messages in the visible area
- **Streaming throttle** (option A): incremental text accumulated in a buffer, merged/refreshed every 50ms
- **Page transition animations**: ChatPage and SideBarPage slide in horizontally

### Data Models

| Model          | Description                                                              |
| -------------- | ------------------------------------------------------------------------- |
| `Message`      | Single message (@Observed), with reasoning/isThinking/isSearching states |
| `Conversation` | A chat session, optionally belonging to a Category (folder)               |
| `Category`     | Folder/category (@Observed), with parentId (multi-level nesting) and color (icon color) |
