# Harmony LLM Chat Categorize

> **[简体中文](README.md) | English**

An AI chat application built on HarmonyOS NEXT, featuring SSE streaming conversations, deep thinking, web search, persistent chat history, and multi-level folder categorization. The architecture follows MVVM with layered design, developed in ArkTS / ArkUI declarative syntax.

## Tech Stack

| Aspect            | Choice                                                                    |
| ----------------- | ------------------------------------------------------------------------- |
| Platform          | HarmonyOS NEXT 6.0.0 (API 20, targetSdkVersion / compatibleSdkVersion)    |
| Language          | ArkTS (strongly typed + declarative)                                      |
| UI Framework      | ArkUI declarative development (@State / @Observed state, LazyForEach)     |
| Data Persistence  | `@kit.ArkData` relationalStore relational database + Preferences storage  |
| Credential Secure | `@kit.AssetStoreKit` encrypted API Key storage (AES256-GCM, keys in TEE)  |
| Networking        | `@kit.NetworkKit` (HTTP SSE streaming, Responses API)                 |
| LLM API           | DeepSeek Responses API (provider preset registry + Provider factory pattern) |
| Web Search        | DeepSeek server-side web_search tool (no local third-party search API) |
| Markdown Rendering | `@luvi/lv-markdown-in` native rendering (LaTeX formulas, code highlight, Mermaid) |

## Features

- **Streaming AI Chat** — SSE token-by-token output; reasoning content (`reasoning_content`) and main text shown in separate channels
- **Deep Thinking (toggleable)** — Uses Responses API `reasoning.effort`: `high` for deep reasoning when on, `low` for lightweight thinking when off
- **Web Search** — DeepSeek server-side `web_search` tool for real-time retrieval; drives the "searching..." state from the stream; auto-marks as degraded when no search event occurs
- **Settings Page** — Pick a provider / enter Key / choose a model in-app; persisted after save, survives restarts
- **Secure Key Storage** — API Keys encrypted via Asset Store Kit (TEE), never written in plaintext; legacy plaintext auto-migrated and purged
- **Multi-level Folder Categorization** — Unlimited folder depth; Favorites tab shows top-level folders with drill-down navigation
- **Folder Management** — Create / rename / move / delete (with confirmation + cascading category-relation removal), 8 selectable icon colors
- **Conversation Archiving** — Move conversations into any folder or back to unclassified; browse by folder
- **Conversation History** — Auto-persisted; sidebar groups by time (Today / Yesterday / 7 days / 30 days / Year-Month)
- **Conversation Management** — Search filter, long-press menu (multi-select/delete), batch delete, swipe from left edge to open history page
- **Message Persistence** — User messages and AI replies (including thinking content) saved in real time; reloadable from history
- **Smart Scroll** — Auto-follows the latest message; re-pins to bottom as Markdown async rendering grows items; pauses following when the user scrolls manually; when not at the bottom, a "back to bottom" floating button appears in the bottom-right corner (tap to force-scroll)
- **Streaming Throttle** — Incremental text merged every 50ms, reducing high-frequency stream updates to ~20fps
- **Concurrent Multi-conversation Streaming** — Each conversation owns an independent StreamTask; switching away keeps the original stream running in the background without cross-writes
- **Pause / Resume Generation** — The send button turns into a pause button while generating; tapping it aborts the request but keeps the received content; network hiccups auto-enter the paused state, and one tap resumes generation from where it left off (reusing the original task and toggles); generated content is throttled-persisted every 2.5s with a `partial` mark, so after the process is killed and the app restarts, "Resume" is restored automatically
- **Structured Error Card** — Generation failures / interruptions are no longer appended into the message body; an error card renders at the bottom of the bubble (category title + unified message + expandable provider raw info / HTTP status), keeping the body clean; Toast and card share the same code-normalized copy
- **Background Streaming Keep-alive** — Requests a `dataTransfer` continuous task when in background with active streams so the SSE connection isn't frozen by the system
- **Keyboard Avoidance** — RESIZE mode pins the input bar to the bottom when the keyboard appears
- **Smart Time Divider** — Auto-shows a divider when message gaps exceed 10 minutes
- **Markdown Rendering** — AI messages natively rendered in Markdown (LaTeX formulas, code highlighting, Mermaid charts); increments auto-re-render during streaming
- **Markdown Rendering Performance** — Lazy rendering for off-screen blocks + threaded rendering, pre-rendering only blocks near the viewport; overlong code blocks auto-collapse and show line numbers; Markdown library preheating eliminates first-open jank in history conversations
- **Markdown Dark Mode Adaptation** — Fully follows the system light/dark mode: code-block / Mermaid themes and LaTeX formula colors switch dynamically with colorMode; font colors use `$r()` resource references
- **Text Selection & Copy** — Long-press select text in AI messages and copy with one tap (writes to the system clipboard yourself); "Copy" button on code blocks; user messages copyable via long-press
- **Conversation Branching** — Regenerate an AI reply (overwrites it) or create a new branch (keeps the old reply as a new variant); cycle variants of the same group via the "current / total" switcher in the bubble action bar; inactive branches are kept in the database and can be switched back anytime
- **Message Editing** — "Edit" on a user message refills the input box (with an edit hint on top); sending then creates a new branch at that position and regenerates the AI reply
- **Delete Single Message** — After a system-dialog confirmation, cascades to delete the message and all its follow-up branches (subtree deletion); auto-resets to a new conversation when everything is deleted
- **Select Text (view original)** — The "More" menu opens a bottom half-modal sheet showing the raw Markdown source before rendering, selectable/copyable via long-press

## Quick Start

### 1. Run the Project

Open the project root with DevEco Studio, wait for dependency sync, connect a device or emulator, and click Run.

### 2. Configure the API

Fill in the in-app **Settings** page (no code changes needed; persisted after saving):

| Field       | Description                                                           |
| ----------- | --------------------------------------------------------------------- |
| Provider    | Drop-down selection, DeepSeek by default (presets maintained in the ModelPresets registry) |
| API Key     | LLM secret key (password input, stored encrypted)                     |
| Model Name  | Drop-down of models available for the current provider; empty = provider default model |

- The endpoint / models / capability toggles for a provider are derived from code-side presets (`ModelPresets.ets`); the Settings page shows them read-only, no manual entry needed
- Web search is provided by DeepSeek's server-side `web_search` tool; no separate search API Key required — just enable the toggle in the input bar
- ⚠️ When unconfigured, chatting is blocked with a prompt guiding you to the Settings page

## Project Structure

```
ChatCategorize/
├── AppScope/                 # App-level config (app icon, app.json5)
├── entry/src/main/
│   ├── ets/
│   │   ├── common/           # Global constants & utilities
│   │   │   ├── AppConstants.ets          # Business constants (folder palette, bubble width ratio)
│   │   │   ├── Utils.ets                 # Utilities (generateId / showToast / delete confirmation)
│   │   │   ├── TimeUtil.ets              # Time grouping & smart time formatting
│   │   │   ├── Logger.ets                # Unified logging wrapper
│   │   │   └── NavTransitionManager.ets  # Page navigation transition animations
│   │   ├── config/           # App configuration
│   │   │   ├── AppConfig.ets             # Config management (Preferences + Asset Store read/write)
│   │   │   ├── SecureKeyStore.ets        # Secure key storage (Asset Store Kit wrapper)
│   │   │   └── ModelPresets.ets          # Provider preset registry (endpoint / models / capabilities)
│   │   ├── database/         # Persistence layer (DAO + Repository)
│   │   │   ├── DatabaseHelper.ets        # Schema creation + shared RdbStore singleton
│   │   │   ├── ConversationDao.ets       # Conversation table CRUD
│   │   │   ├── MessageDao.ets            # Message table CRUD
│   │   │   ├── CategoryDao.ets           # Folder table CRUD
│   │   │   ├── ConversationRepository.ets# Cross-table aggregation / transactions
│   │   │   └── CategoryRepository.ets    # Folder tree + cascading delete
│   │   ├── service/          # Service layer (Provider factory pattern)
│   │   │   ├── LLMProviderFactory.ets    # LLM Provider factory
│   │   │   ├── SearchProviderFactory.ets # Search Provider factory (extension point, placeholder impl)
│   │   │   ├── StreamTask.ets            # Single streaming task (isolated buffer/throttle/placeholder)
│   │   │   ├── BackgroundRunGuardService.ets # Background keep-alive
│   │   │   └── provider/
│   │   │       ├── LLMProvider.ets       # LLM abstract interface (SSE streaming)
│   │   │       ├── DeepSeekProvider.ets  # DeepSeek implementation (Responses API)
│   │   │       ├── SearchProvider.ets    # Search abstract interface (extension point)
│   │   │       └── NotImplementedSearchProvider.ets # Placeholder for custom web search
│   │   ├── viewmodel/        # State management layer (MVVM's VM)
│   │   │   ├── ChatViewModel.ets         # Chat state & message flow
│   │   │   ├── FolderViewModel.ets       # Folder tree state
│   │   │   └── SideBarViewModel.ets      # Sidebar history/favorites state
│   │   ├── model/            # Data models (@Observed observable objects)
│   │   │   ├── Message.ets               # Message model (thinking/search states + branch fields)
│   │   │   ├── Conversation.ets          # Conversation model
│   │   │   ├── Category.ets              # Folder/category model
│   │   │   ├── FolderParams.ets          # Folder navigation params
│   │   │   └── SideBarParams.ets         # Sidebar route params
│   │   ├── components/       # UI components (grouped by responsibility)
│   │   │   ├── chat/                     # Chat-related
│   │   │   │   ├── MessageBubble.ets     # Chat bubble (with thinking block & action bar)
│   │   │   │   └── ChatInput.ets         # Input bar (deep thinking / web search toggles)
│   │   │   ├── item/                     # List items
│   │   │   │   ├── ConversationItem.ets  # History conversation list item (long-press menu)
│   │   │   │   └── FolderItem.ets        # Folder list item (colored icon)
│   │   │   └── dialog/                   # Dialogs
│   │   │       ├── RenameInputDialog.ets # Generic text input dialog
│   │   │       ├── EditFolderDialog.ets  # Edit folder dialog
│   │   │       └── FolderPickerDialog.ets# Folder picker
│   │   ├── pages/            # Pages (ArkUI routes)
│   │   │   ├── HomePage.ets              # Home page (navigation entry)
│   │   │   ├── ChatPage.ets              # Main chat page
│   │   │   ├── SideBarPage.ets           # Sidebar (Favorites / History tabs)
│   │   │   ├── FolderPage.ets            # Folder page (subfolders + conversations, multi-level)
│   │   │   └── SettingsPage.ets          # Settings page (API config form)
│   │   ├── entryability/     # Ability entry
│   │   │   └── EntryAbility.ets          # Preloads config in onCreate; keep-alive on foreground/background
│   │   └── entrybackupability/           # Backup & restore capability
│   │       └── EntryBackupAbility.ets
│   ├── resources/            # Resources (string / color / float / media / profile)
│   └── module.json5          # Module config (INTERNET / KEEP_BACKGROUND_RUNNING permissions)
├── build-profile.json5       # Build config (local signing, not committed)
├── oh-package.json5          # Root dependency management
└── hvigorfile.ts             # Build scripts
```

## Core Design

### 1. AppConfig — Config Management (Preferences + Asset Store)

- Idempotently preloaded by `AppConfig.getInstance().init(context)` in `EntryAbility.onCreate`
- **Non-sensitive fields** (baseUrl / model / searchBaseUrl) → stored in plaintext Preferences
- **Sensitive fields** (apiKey / searchApiKey) → encrypted in SecureKeyStore, never written in plaintext
- Legacy migration: detects plaintext keys left in Preferences, auto-migrates them to Asset Store, then deletes the plaintext residue
- `isConfigured()` validates the three required LLM fields and blocks chatting with a prompt when unconfigured
- Defaults to empty strings; **no keys hardcoded**

### 2. SecureKeyStore — Secure Key Storage

- Built on Asset Store Kit (analogous to iOS Keychain / Android Keystore); keys stored in the hardware secure area (TEE)
- AES256-GCM ciphertext on disk; plaintext can't be recovered even if app data is read or backed up
- `SyncType.NEVER`: excluded from cloud sync / cloud backup to prevent key leakage
- Provides `save` / `get` / `remove` static methods; saving an empty string clears the old key

### 3. LLM Provider — SSE Streaming Chat (Factory Pattern)

```
User input → ChatViewModel → LLMProviderFactory.create()
  → DeepSeekProvider.sendMessage() (Responses API, HTTP POST, stream: true)
  → Parses SSE events in event: + data: pairs
  → response.reasoning_text.delta outputs reasoning deltas
  → response.output_text.delta outputs main-text deltas
  → response.completed / incomplete / failed marks end or failure
```

- `LLMProvider` defines the abstract interface (streaming callbacks); `DeepSeekProvider` implements DeepSeek's Responses API calls
- Request body follows the Responses API: `input` message list + `reasoning.effort` (reasoning intensity) + `tools.web_search` (web search)
- `LLMProviderFactory` dispatches providers by `providerId`; adding a provider only requires appending a preset to ModelPresets and, if needed, registering a new Provider
- SSE events are parsed in `event:` + `data:` JSON pairs (also compatible with data JSON carrying its own type field); incomplete chunks are buffered
- Connect timeout 15s, read timeout 120s (multi-stage thinking / web search may pause increments for a while)
- Deep thinking uses `reasoning.effort`: `high` when on, `low` when off (the Responses API has no full-off switch); the `deepThinking` toggle is passed from ChatInput
- **Unified error model** (`LLMError`): provider errors (HTTP status codes / vendor-specific error structures) are normalized inside each Provider into a unified `ErrorCode` + `category` (config / auth / rate_limit / context / output / server / network); `retryable` decides whether "Resume" is kept after an error; copy is decoupled from codes (`errorMessageResource()` resolves string.json by code, no hardcoded text) and serialized into the message table's `error_text` column, so error cards survive restarts
- **Error-code mapping**: HTTP 401 → `AUTH_INVALID_KEY`, 429 → `RATE_LIMITED`, 400 (message containing context/token) → `CTX_OVERFLOW`, 5xx → `SRV_ERROR`; `response.failed` maps by the vendor `error.code` characteristics; read timeout / connection drop / request failure are distinguished as `NET_TIMEOUT` / `NET_DISCONNECTED` / `NET_REQUEST_FAILED`
- **Output truncation** (`onIncomplete`): `response.incomplete` means "generation did not finish" (hit `max_output_tokens`); the generated content is fully kept and enters the resumable paused state (same as "Resume"), unlike non-resumable hard errors
- **Multi-stage thinking timing**: `StreamTask.beginThinking() / endThinking()` accumulate `thinkingMs` across stages (Agent-style "think → text → think again" switching), so "thought (Xs)" reflects the whole session, not just the first segment

### 4. Web Search — Server-side Web Search

```
Web search on → ChatViewModel → DeepSeekProvider (request body carries tools.web_search)
  → Server executes the web_search tool, emitting web_search_call events in the stream
  → response.web_search_call.in_progress / searching → onWebSearchStart ("searching...")
  → response.web_search_call.completed → onWebSearchEnd (resume thinking / answering)
```

- Web search is executed server-side by DeepSeek (Responses API `web_search` tool); no third-party search API is called locally and no search Key is needed
- The search state is driven by server stream events: `onWebSearchStart` / `onWebSearchEnd` update the UI's "searching..." hint in real time
- Receiving a main-text delta is the fallback exit from the searching state; if search was requested but no search event appeared in the whole stream → marked as failed (degradation hint)
- The `SearchProvider` interface and `SearchProviderFactory` remain as the extension point for "custom web search API in the future" (the placeholder implementation is always unavailable)

### 5. DatabaseHelper — Relational Database (DAO + Repository Layers)

Based on `relationalStore`, three tables:

| Table           | Fields                                                                                             | Description                                  |
| --------------- | -------------------------------------------------------------------------------------------------- | -------------------------------------------- |
| `conversation`  | id, title, category_id, created_at, updated_at                                                     | Conversation table                           |
| `message`       | id, conversation_id, role, content, reasoning, generation_status, error_text, created_at, parent_id, branch_group_id, variant_index, is_active | Message table (thinking content, generation status, error info & branch fields) |
| `category`      | id, name, parent_id, color, sort_order, created_at                                                 | Folder/category table (multi-level nesting)  |

- Layered design: `*Dao` for flat single-table CRUD (errors propagate up); `*Repository` for cross-table aggregation and transactions (folder tree, cascading delete)
- Singleton pattern; `init()` idempotently creates tables (IF NOT EXISTS)
- Legacy DB compatibility: if the message table lacks branch / generation-status / error columns, `ensureMessageColumns()` adds them idempotently via ALTER TABLE (including `generation_status` and `error_text`)
- High-frequency query indexes: `message(conversation_id)`, `conversation(updated_at DESC)`
- Delayed conversation insertion: a record is created only on the first user message, avoiding empty conversations polluting history
- Deleting a conversation cascades message deletion (IN condition); deleting a folder recursively collects descendants via `deleteCategoryCascade()` and removes their category relations (conversations themselves are kept)
- All API calls wrapped in try-catch, silently degrading on exceptions

### 6. ViewModel — State Management Layer

- `ChatViewModel`: chat message flow, streaming-callback-driven UI updates, smart scroll, conversation branching (regenerate / new branch / edit / switch)
- `FolderViewModel`: folder tree construction, multi-level navigation, folder CRUD state
- `SideBarViewModel`: history grouping, Favorites tab, batch selection state
- Decouples pages from the data layer; ViewModels bridge DAO/Repository and ArkUI state (the heart of MVVM)

### 7. StreamTask — Concurrent Multi-conversation Streaming

- One in-progress stream = one `StreamTask` instance (owning text/thinking buffers, throttle timer, AI placeholder message)
- `ChatViewModel` holds `Map<conversationId, StreamTask>`: switching to conversation B keeps A's stream progressing in the background with no buffer cross-writes
- Send limiting is per-conversation (`isStreamingFor`); streams in different conversations don't affect each other
- Async operations (loading conversations / fetching titles) use "stale result guards": re-validating the conversation id after `await` to prevent UI confusion from rapid switching
- On page destroy, all tasks are `clearTimer()`'d to prevent lingering timers from firing stale writes

### 8. Conversation Branching — Branch Chain Model

Each message records `parentId` (the message it replies to; empty for root user messages), `branchGroupId` (= parentId; messages in the same group are variant siblings), `variantIndex` (variant ordinal within the group, starting at 0), and `isActive` (whether it lies on the current active branch; the list renders the active chain only):

```
U1(root) ── A1 (variant 0) ── U2 ── A2          ← active chain (highlighted)
   │           └ A1' (variant 1)                  ← same-group variant (inactive, switchable back)
```

- **Regenerate** (`regenerateMessage`): overwrites the current AI reply in place without creating a new variant
- **New Branch** (`createBranch`): creates a new variant with the same parent and regenerates; the old reply and its follow-up chain are deactivated (`deactivateBranchFrom`) but kept in the database
- **Message Edit** (`startEdit` / `editUserMessage`): "Edit" on a user message refills the input box (`editingMessageId` + `editingPrefill`); sending creates a new user-message variant and regenerates the AI reply
- **Delete Single Message** (`deleteMessage`): breadth-first traversal along parentId collects the message + all descendants → removed from DB and memory cache in sync → terminates the stream task if it targets a deleted message → rebuilds the list; auto-resets to a new conversation when everything is deleted
- **Switch Branch** (`switchBranch`): cycles variants ±1 within the group; `rebuildActiveChain()` deactivates all → lights up the target variant's ancestor path → extends its active follow-up chain → persists → reloads the list (pre-scroll locks the viewport and re-aligns to the target message bottom after reload to avoid flicker; see §10)
- **Variant count** (`getVariantInfo`): returns `{ current, total }` to drive the "current / total" switcher (shown only when multiple variants exist)
- `allMessages` caches all messages of the current conversation (including inactive variants) as the single source of truth for branch switching / variant counting / active-chain rebuilds
- Legacy data compatible: when all messages have empty `parentId`, they render in chronological order with no branching UX impact
- The action bar is hidden entirely while streaming (`message.isStreaming` is @Trace), preventing mis-taps from the root

### 9. BackgroundRunGuardService — Background Streaming Keep-alive

- Background: the system freezes network resources ~2s after an app goes to background and releases them ~12s later, cutting off SSE streaming connections
- Solution: while in background **and** streams are actively running, request a `dataTransfer` continuous task (`backgroundTaskManager.startBackgroundRunning`) to keep the network connection alive
- The keep-alive count only counts `isStreaming=true` tasks (paused tasks have already aborted their network requests, so no keep-alive needed)
- Immediately calls `stopBackgroundRunning` when all tasks finish or the app returns to foreground, avoiding resource usage
- Prerequisites: `ohos.permission.KEEP_BACKGROUND_RUNNING` permission + `backgroundModes: ["dataTransfer"]` in EntryAbility

### 10. ChatPage — Rendering Optimizations

- **LazyForEach**: custom `IDataSource` for lazy loading, rendering only messages in the visible area
- **Streaming throttle**: incremental text accumulated in a buffer, merged/refreshed every 50ms
- **Smart Scroll (smooth follow)**: streaming follow switched to a 50ms debounce + 200ms EaseOut animation (`scrollToBottomSmooth`, animated via a `getUIContext().animateTo` executor injected by the page), eliminating the "jumping" feel of token-by-token refreshes; only one animation group at a time to avoid animation pile-up jitter
- **scrollEdge-first positioning**: `scrollToBottom()` prefers `scrollEdge(Edge.Bottom)` to jump straight to the bottom edge (doesn't rely on whether the last item has been lazy-rendered, more reliable), falling back to `scrollToIndex(last, END)` on platforms that don't support it
- **Repeated pin-after-load retries**: `pinToBottomAfterLoad()` retries at 120ms intervals up to 6 times, solving "conversations with many branches / heavy Markdown fail to scroll to the last message on open" (lazy loading + async Markdown rendering make item heights known too late)
- **First-frame layout hold**: the List's first `onAreaChange` triggers `onListFirstLayout()`; pin-to-bottom requests issued before layout is ready are held (`pendingPinToBottom`), avoiding "sticking at the top when opened" during the transition back from the sidebar
- **Instant re-pin on item height change**: ListItem `onAreaChange` reports the height delta (`onListItemHeightChanged`); when async Markdown rendering grows an item, the list re-pins to bottom immediately — faster than fixed-interval retries and idle-free; skipped while streaming, left to the animated follow
- **Variant-switch scroll alignment (anti-flicker)**: the target variant and the current message are "same-position siblings" — first `scrollToIndex(fromId, END)` on the old list to lock the viewport at that position (the old item is already rendered, so it always works), then after `replaceAll` reloads, `scrollMessageToBottom(targetId)` (`ScrollAlign.END`, exempt from the auto-follow guard) aligns the target message bottom (action bar) with the viewport bottom, avoiding the "bounce to top then jump back" flicker after data replacement
- **Scroll guard refactor**: `shouldAutoScroll()` (= `isAtBottom && !isUserScrolling`) uniformly decides auto-follow; the low-level `scrollToBottomEdge()` (unguarded, `scrollEdge` first, falling back to `scrollToIndex` on some versions) is shared by `scrollToBottom` / `jumpToBottom`
- **Markdown library preheating**: ChatPage embeds a `Visibility.Hidden` zero-size `Markdown` component that triggers lv-markdown-in's worker initialization (a process-wide singleton), eliminating "body jank" on first open of a history conversation
- **Page transition animations**: ChatPage and SideBarPage slide in horizontally
- **Back key interception**: ChatPage is the bottom-of-stack main page (pushed via isEntry), so the system back key means "exit the app"; `onBackPressed` intercepts and calls `terminateSelf()` to exit directly, preventing the NavDestination from being popped back to an empty Navigation home (NavBar)

### 11. MessageBubble — Markdown Rendering & Text Interaction

- AI message content is natively rendered by the `Markdown` component from `@luvi/lv-markdown-in` (full markdown syntax, LaTeX formulas, code highlighting; mermaid handled by the library's built-in renderer, no custom WebView needed); user messages stay as plain text (adaptive bubble width)
- **Rendering performance**: `setLazyRender(true)` + `setLazyPreloadBlockCount(2)` render off-screen blocks as lightweight placeholders, pre-rendering only a few blocks near the viewport; `setThreadRenderEnable(true)` enables threaded rendering; `setCodeBlockIdxState(true)` shows line numbers on code blocks and `setCodeBlockAutoCollapseEnable(true)` auto-collapses code blocks over the threshold (10 lines by default), easing long-code-block rendering pressure
- **Dark mode adaptation**: font colors use `$r()` resource references (the system auto-loads matching values from the dark/ directory); code-block / Mermaid themes and LaTeX formula colors are switched dynamically by listening to the system `colorMode` via `on('environment')`, with the listener removed in `aboutToDisappear` to prevent leaks
- **Text copying**: `setTextSelectionEnable(true)` enables long-press selection and `setTextSelectionCopyListener` writes to the system clipboard (with success/failure Toasts); code blocks register the "Copy" button via `setCodeCopyListener`; user messages support long-press copy via `copyOption(CopyOptions.LocalDevice)`
- **Action bar**: user messages get [Delete] [Copy] [Edit] [Branch switcher] at bottom-right; AI messages get [Branch switcher] [Copy] [More] at bottom-left and [Delete] [New branch] [Regenerate] at bottom-right; the "More" button opens a vertical menu: Copy / Select Text / New Branch / Regenerate / Delete (danger-styled, at the bottom); the "current / total" switcher shows when multiple variants exist
- **Select Text (view original)**: "More" → "Select Text" opens a bottom half-modal sheet via `bindSheet($$isTextSheetShow)` showing the raw Markdown source before rendering (`copyOption(CopyOptions.LocalDevice)` for long-press select/copy); sheet height = window height − status bar − title bar, aligned with the page title bar's bottom edge; the $$ two-way binding auto-resets the state when closed
- **Delete message**: the trash button opens a system dialog for confirmation (actually deleting only when `result.index === 1`); on confirm, the ViewModel cascades along parentId to delete the message and all its follow-up branches
- During streaming, `text` is a @Prop and content increments auto-re-render; `Message.isStreaming` marks an in-progress stream, cleared on completion (including errors)

## Data Models

| Model           | Description                                                                                          |
| --------------- | ----------------------------------------------------------------------------------------------------- |
| `Message`       | Single message (@Observed), with reasoning/isThinking/isSearching states; branch fields parentId/branchGroupId/variantIndex/isActive |
| `Conversation`  | A chat session, optionally belonging to a Category (folder)                                           |
| `Category`      | Folder/category (@Observed), with parentId (multi-level nesting) and color (icon color)              |

## Permissions

| Permission                           | Purpose                                    |
| ------------------------------------ | ------------------------------------------- |
| `ohos.permission.INTERNET`           | LLM requests (web search runs server-side)     |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | Keep the SSE connection alive in background |
