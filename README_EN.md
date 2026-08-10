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
- **Markdown Rendering**: `@luvi/lv-markdown-in` native Markdown rendering (LaTeX formulas, code highlighting, Mermaid diagrams)

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
- **Markdown Rendering** — AI messages rendered natively in Markdown (LaTeX formulas, code highlighting, Mermaid diagrams); increments auto-re-render during streaming
- **Markdown Dark Mode Adaptation** — Rendering fully follows system light/dark mode: code block & Mermaid themes and LaTeX formula colors switch dynamically with colorMode; font colors use `$r()` resource references (auto-loaded from the dark/ directory)
- **Text Selection & Copy** — Long-press select text in AI messages and copy with one tap (writes to the system clipboard yourself); "Copy" button on code blocks; user messages copyable via long-press (CopyOptions.LocalDevice)
- **Conversation Branching** — Regenerate an AI reply (overwrites it) or create a new branch (keeps the old reply as a new variant); cycle through variants of the same group via the "current / total" switcher in the bubble action bar; inactive branches are kept in the database and can be switched back anytime
- **Message Editing** — "Edit" on a user message refills the input box (with an edit hint on top); sending then creates a new branch at that position and regenerates the AI reply
- **Delete Single Message** — Trash button in the message action bar (AI messages: inside the "More" menu too); after a system-dialog confirmation, cascades to delete the message and all its follow-up branches (subtree deletion); when everything is deleted, auto-resets to a new conversation and deletes the now-empty conversation record
- **Select Text (view original)** — "Select Text" in the AI message "More" menu opens a bottom half-modal sheet showing the raw Markdown source before rendering, selectable/copyable via long-press (bypasses the rendered view's text-selection limits)

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
│   │   │   ├── AppConfig.ets       # Config management (Preferences + Asset Store read/write)
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
| `message`      | id, conversation_id, role, content, reasoning, created_at, parent_id, branch_group_id, variant_index, is_active | Message table (includes thinking content & branch fields) |
| `category`     | id, name, parent_id, color, sort_order, created_at             | Folder/category table (multi-level nesting)   |

- Layered design: `*Dao` for flat single-table CRUD (errors propagate up); `*Repository` for cross-table aggregation and transactions (folder tree, cascading delete)
- Singleton pattern; `init()` idempotently creates tables (IF NOT EXISTS)
- Legacy DB compatibility: if the message table lacks branch columns, `ensureMessageColumns()` adds them idempotently via ALTER TABLE (fresh installs already have all columns)
- High-frequency query indexes: `message(conversation_id)`, `conversation(updated_at DESC)`
- Delayed conversation insertion: a record is created only on the first user message, avoiding empty conversations polluting history
- Deleting a conversation cascades message deletion (IN condition)
- Folder tree: empty `parent_id` means top-level; `getCategorySubtreeIds()` collects descendant nodes; moving a folder excludes itself to prevent cycles
- Cascading folder delete: `deleteCategoryCascade()` recursively collects descendants, then removes their category relations (conversations themselves are kept)
- All API calls wrapped in try-catch, silently degrading on exceptions

### ViewModel — State Management Layer

- `ChatViewModel`: chat message flow, streaming-callback-driven UI updates, smart scroll state, conversation branching (regenerate / new branch / edit / switch)
- `FolderViewModel`: folder tree construction, multi-level navigation, folder CRUD state
- `SideBarViewModel`: history grouping, Favorites tab, multi-select state
- Decouples pages from the data layer; ViewModels bridge DAO/Repository and ArkUI state

### StreamTask — Concurrent Multi-conversation Streaming

- One in-progress stream = one `StreamTask` instance (owning text/thinking buffers, throttle timer, AI placeholder message)
- `ChatViewModel` holds `Map<conversationId, StreamTask>`: switching to conversation B keeps A's stream progressing in the background with no buffer cross-writes
- Send limiting is per-conversation (`isStreamingFor`); streams in different conversations don't affect each other
- Async operations (loading conversations / fetching titles) use "stale result guards": re-validating the conversation id after `await` to prevent UI confusion from rapid switching
- On page destroy, all tasks are `clearTimer()`'d to prevent lingering timers from firing stale writes

### Conversation Branching — Branch Chain Model

Branch chain model: each message records `parentId` (the message it replies to; empty for root user messages), `branchGroupId` (= parentId; messages in the same group are variant siblings), `variantIndex` (variant ordinal within the group, starting at 0), and `isActive` (whether it lies on the current active branch; the list renders the active chain only).

```
U1(root) ── A1 (variant 0) ── U2 ── A2          ← active chain (highlighted)
   │           └ A1' (variant 1)                  ← same-group variant (inactive, switchable back)
```

- **Regenerate** (`regenerateMessage`): overwrites the current AI reply in place without creating a new variant (reuses the old message object)
- **New Branch** (`createBranch`): creates a new variant with the same parent and regenerates; the old reply and its follow-up chain are deactivated (`deactivateBranchFrom`) but kept in the database
- **Message Edit** (`startEdit` / `editUserMessage`): "Edit" on a user message refills the input box (`editingMessageId` + `editingPrefill`); sending creates a new user-message variant and regenerates the AI reply
- **Delete Single Message** (`deleteMessage`): blocked while streaming; DFS collects the message itself + all descendants (any branch variant, avoiding dangling parent pointers) → removed from memory and DB (transactionally) in sync → terminates the stream task if it targets a deleted message (defensive; normally unreachable) → auto-exits edit mode when the edited message is deleted → rebuilds the active chain and reloads the list
- **Switch Branch** (`switchBranch`): cycles variants ±1 within the group; `rebuildActiveChain()` deactivates all → lights up the target variant's ancestor path → extends its active follow-up chain (falling back to the earliest variant when no active child) → persists → reloads the list
- **Variant count** (`getVariantInfo`): returns `{ current, total }` to drive the "current / total" switcher in the bubble action bar (shown only when multiple variants exist)
- `allMessages` caches all messages of the current conversation (including inactive variants) as the single source of truth for branch switching / variant counting / active-chain rebuilds
- Legacy data compatible: when all messages have empty `parentId`, they render in chronological order with no branching UX impact
- The action bar is hidden entirely while streaming (`message.isStreaming` is @Trace, auto-restored when the stream ends), preventing mis-taps from the root

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
- **Back key interception**: ChatPage is the bottom-of-stack main page (pushed via isEntry), so the system back key means "exit the app"; `onBackPressed` intercepts and calls `terminateSelf()` to exit directly, preventing the NavDestination from being popped back to an empty Navigation home (NavBar)

### MessageBubble — Markdown Rendering

- AI message content is natively rendered by the `Markdown` component from `@luvi/lv-markdown-in`: full markdown syntax, LaTeX formulas, code highlighting; mermaid code blocks are handled by the library's built-in Mermaid rendering (bundled mermaid.main.js, no custom WebView needed)
- User messages stay as plain text (adaptive bubble width)
- **Dark mode adaptation**: font colors use `$r()` resource references (the system auto-loads matching values from the dark/ directory on light/dark switch); code block & Mermaid themes (string `'light'/'dark'` only) and LaTeX formula colors (hex numbers only) are switched dynamically by listening to the system `colorMode` via `on('environment')`, with the listener removed in `aboutToDisappear` to prevent leaks
- **Text copying**: since lv-markdown-in v3.1.0 the library no longer copies to the clipboard itself — `setTextSelectionEnable(true)` enables long-press selection and `setTextSelectionCopyListener` writes to the system clipboard (with success/failure Toast); code blocks register the "Copy" button via `setCodeCopyListener`; user messages support long-press copy via `copyOption(CopyOptions.LocalDevice)`
- **Action bar**: user messages get [Delete] [Copy] [Edit] [Branch switcher] at bottom-right; AI messages get [Branch switcher] [Copy] [More] at bottom-left and [Delete] [New branch] [Regenerate] at bottom-right; the "More" button (dot_grid_2x2) opens a vertical menu: Copy / Select Text / New Branch / Regenerate / Delete (danger-styled, at the bottom); the "current / total" switcher shows when multiple variants exist; icon color is unified via the `operation_icon` resource (light #666666 / dark #8E8E8E), buttons always enabled — **the action bar is hidden entirely while streaming** (`message.isStreaming` is @Trace, auto-restored when the stream ends), preventing mis-taps from the root
- **Select Text (view original)**: AI message "More" menu → "Select Text" opens a bottom half-modal sheet via `bindSheet($$isTextSheetShow)`: a title row on top + a scrollable body below (raw Markdown source before rendering, `copyOption(CopyOptions.LocalDevice)` for long-press select/copy); sheet height = window height − status bar − title bar, so its top aligns with the page title bar's bottom edge (`textSheetHeight()` computed dynamically, 500vp fallback on error); the $$ two-way binding auto-resets the state when dragged/backdrop-tapped closed
- **Delete message**: the trash button (user messages: shown directly; AI messages: in both the action bar and the "More" menu) opens a system dialog for confirmation ("Cancel / Delete" with a danger-styled Delete, actually deleting only when `result.index === 1` to avoid mis-taps); on confirm, the ViewModel cascades along `parentId` to delete the message and all its follow-up branches
- During streaming, `text` is a @Prop and content increments auto-re-render; `Message.isStreaming` marks an in-progress stream, cleared on completion (including errors)

### Data Models

| Model          | Description                                                              |
| -------------- | ------------------------------------------------------------------------- |
| `Message`      | Single message (@Observed), with reasoning/isThinking/isSearching states; branch fields parentId/branchGroupId/variantIndex/isActive |
| `Conversation` | A chat session, optionally belonging to a Category (folder)               |
| `Category`     | Folder/category (@Observed), with parentId (multi-level nesting) and color (icon color) |
