# Harmony LLM Chat Categorize (Cloud)

> **English | [简体中文](README.md)**

A cloud-integrated AI chat app for HarmonyOS NEXT. The client provides full chat capabilities (SSE streaming, deep thinking, web search, multi-level folder categorization) and syncs data through AGC cloud development (Cloud DB + Cloud Functions + Auth). Built with an MVVM + layered architecture using ArkTS / ArkUI declarative development.

## Tech Stack

| Dimension         | Choice                                                            |
| ----------------- | ----------------------------------------------------------------- |
| Platform          | HarmonyOS NEXT (API 24)                                           |
| Language / UI     | ArkTS / ArkUI declarative (@Observed state, LazyForEach)          |
| Persistence       | relationalStore + Preferences                                     |
| Credential safety | Asset Store Kit (API Key encrypted in TEE)                        |
| Network           | NetworkKit (HTTP SSE streaming, Responses API)                    |
| LLM API           | DeepSeek Responses API (extensible Provider factory)              |
| Web search        | DeepSeek server-side web_search tool                              |
| Markdown          | @luvi/lv-markdown-in native rendering (LaTeX / code highlight / Mermaid) |
| Share parsing     | marked ArkTS port ([Harmony-Markdown-Editor](https://github.com/electronicminer/Harmony-Markdown-Editor), MIT) |
| Document parsing  | @ohos/jszip + in-house OOXML extractor (docx / pptx / xlsx → Markdown), ArkWeb + deck-ir / docx-preview (layout screenshots of docx/pptx on vision models), PDF Kit (per-page PDF rendering) |
| Cloud sync        | AGC Cloud DB (Cloud Foundation Kit, bidirectional sync with local RDB) |
| Cloud auth        | AGC Auth (anonymous sign-in)                                      |
| Cloud functions   | Cloud Functions (id-generator for UUIDs)                          |

## Features

- **Streaming chat** — SSE token-by-token output; thinking and main text in separate channels
- **Thinking effort** — four levels (Off / Low / High / Max)
- **Web search** — search terms and browsed pages visualized in real time, with jump support
- **Pause / resume** — abort mid-generation while keeping content; one-tap resume; recoverable after restart
- **Conversation branches** — change answer / generate new reply / switch branch; old branches switchable back
- **Edit / delete messages** — editing creates a new branch in place; deletion cascades
- **Folder categorization** — unlimited depth; tree-style picker for moving conversations; multi-select batch ops (delete / unfavorite / move)
- **History** — auto-persisted, time-grouped, global search / multi-select / batch delete; titles are auto-generated after the first Q&A round
- **Global search** — matches titles and message content, grouped by conversation, with hit positioning
- **Secure key storage** — API Key encrypted in TEE; legacy plaintext auto-migrated
- **Account login / cloud sync** — AGC Auth anonymous sign-in; full bidirectional sync between local data and AGC Cloud DB (last-write-wins merge); the "Account" page shows sync status and offers one-tap manual sync
- **Model config** — a dedicated page to configure provider / model / API Key
- **Background keep-alive** — continuous task while streaming in background
- **Immersive UI** — full-screen edge-to-edge; system bars blend into the page
- **Multi-device adaptation** — breakpoint-driven layouts for phones / tablets / foldables, and folding/unfolding rearranges in real time
- **Smart scroll** — auto-pin while generating, pause on manual scroll, "back to bottom" button
- **Markdown rendering** — native rendering + performance optimizations + dark-mode support
- **Text interaction** — long-press copy, code-block copy, raw-text viewer
- **Image input** — With vision models, send photos from gallery or camera (auto-compressed, up to 9 per message); tap any message image for a fullscreen preview; add or remove images when editing a message
- **File input** — Send txt / md / pdf / docx / pptx / xlsx attachments; content is auto-extracted for the AI to understand (see Core Design for details)
- **Share** — one-tap share of messages / conversations as plain text, Markdown, HTML, a long image, or PDF; AI replies keep their rich formatting; long conversations are exported per Q&A round into a long image / multi-page PDF

## Quick Start

### 1. Run the project

Open the `Application/` directory in DevEco Studio, wait for dependency sync, connect a device/emulator, and click Run.

### 2. Configure the API

Fill in the in-app "Settings → Model config" page (no code changes, persisted after save):

| Field     | Description                                               |
| --------- | --------------------------------------------------------- |
| Provider  | Dropdown; currently only DeepSeek is supported (presets in ModelPresets) |
| API Key   | LLM secret (password input, encrypted storage)            |
| Model     | Dropdown of the provider's models; empty uses the default |

- Endpoint / models / capability flags are derived from code presets (`ModelPresets.ets`) and shown read-only
- Web search is provided by the DeepSeek server

### 3. Deploy the cloud (CloudProgram)

Cloud sync depends on AGC cloud development. Configure it in [AppGallery Connect](https://developer.huawei.com/consumer/en/service/josp/agc/index.html) first:

1. Create an app (bundleName must match the client) and enable **Auth service** (allow anonymous sign-in) and **Cloud DB**
2. In Cloud DB, create and deploy the three object types from `CloudProgram/clouddb/objecttype/` (conversation / message / category)
3. Deploy the `id-generator` cloud function (generates UUIDs)
4. Download `agconnect-services.json` and place it under `Application/AppScope/resources/rawfile/` (not version-controlled)
5. Run the app, open "Settings → Account login", and tap "Sync now" to initialize auth and run the first sync

## Project Structure

```
ChatCategorizeCloud/
├── Application/                  # HarmonyOS client (cloud-integrated)
│   ├── AppScope/                 # App-level config (incl. cloud DB schema.json, agconnect-services.json)
│   ├── entry/src/main/
│   │   ├── ets/
│   │   │   ├── common/           # Constants & utilities (markdown/ = marked port core; ChatBridge cross-page bus, DeviceAdapt breakpoints)
│   │   │   ├── config/           # App config & key storage
│   │   │   ├── database/         # Data layer (DAO + Repository)
│   │   │   ├── service/          # Service layer (Provider factory + StreamTask + sync/ cloud sync)
│   │   │   ├── viewmodel/        # State layer (MVVM)
│   │   │   ├── model/            # Data models
│   │   │   ├── components/       # UI components (chat / common / dialog / item / panel)
│   │   │   ├── pages/            # Pages (incl. AccountSyncPage, ModelConfigPage)
│   │   │   ├── entryability/     # Ability entry
│   │   │   └── entrybackupability/# Backup & restore
│   │   ├── resources/            # Resources
│   │   └── module.json5          # Module config & permissions
│   ├── cloud_objects/            # Client cloud objects (generated by the Cloud Objects compiler; calls cloud functions)
│   ├── build-profile.json5       # Build config (local signing, not committed)
│   ├── oh-package.json5          # Dependency management (@hw-agconnect/auth)
│   └── hvigorfile.ts             # Build script
└── CloudProgram/                 # Cloud development
    ├── clouddb/                  # Cloud DB (object types: conversation / message / category)
    ├── cloudfunctions/           # Cloud functions (id-generator)
    ├── cloud-config.json         # AGC project config
    └── package.json
```

## Core Design

### 1. Config & Key Security
- Non-sensitive items (baseUrl / model) use Preferences plaintext storage; the API Key is encrypted via Asset Store Kit (TEE + AES256-GCM) and never cloud-synced
- Legacy plaintext keys auto-migrate and are purged; no hardcoded secrets

### 2. LLM Provider — Factory Pattern
- `LLMProvider` abstract interface + `DeepSeekProvider` implementation (Responses API, SSE streaming); the factory dispatches by providerId, and adding a provider only needs a preset
- Requests carry `reasoning.effort` (thinking strength) and `tools.web_search`; vision models support image input (`input_image` content blocks, Base64 inline); unified error model; `response.incomplete` enters the resumable state

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
- Image/PDF export is segmented: a hidden host-page layer (ExportCardLayer) renders each Q&A round and screenshots them one by one; ImageMerger stitches them into one long image, PdfExporter splits them across A4 pages (works around the unusable in-sheet snapshot and the render-buffer height limit)

### 10. Background Keep-alive
- Requests a `dataTransfer` continuous task while streaming in background, released when all finish or the app returns to foreground (needs `KEEP_BACKGROUND_RUNNING` permission)

### 11. Immersive System Bars
- Full-screen layout + transparent system bars with dark/light adaptation; bar heights injected into AppStorage and explicitly avoided by pages (since `safeAreaPadding` fails on fixed-height components)

### 12. File Attachment Parsing — FileParser
- `service/FileParser.ets` wraps the system document picker (DocumentViewPicker, no storage permission) and parsing: txt/md are read as UTF-8 text (truncated); docx/pptx/xlsx are extracted to Markdown text by `service/OoxmlParser.ets` (@ohos/jszip unzip + XmlPullParser streaming OOXML XML — docx paragraphs / headings / tables, pptx per-slide text, xlsx per-sheet tables with sharedStrings); on vision models, docx/pptx instead go through `service/OfficeHtmlParser.ets` (hidden ArkWeb + deck-ir/docx-preview layout) for per-page screenshots; since API 20 lacks `getTextContent`, PDFs are rendered page-by-page via PDF Kit into PixelMap → JPEG Base64 (≤100 pages; total Base64 capped at 12MB to protect the request body)
- Files are dispatched by channel in `DeepSeekProvider.buildApiContent`: txt/md and Office extracted text is merged into the `input_text` block with a `【File xx content】` marker (works on every model); docx/pptx (vision models) / PDF pages become per-page `input_image` vision blocks (vision models only, with fallback guards at pick / send / edit / provider layers)
- Limits & UX: one file ≤20MB; extracted text (txt/md/docx/pptx/xlsx) truncated at 30k chars; file cards shown in message bubbles, and files can be added/removed when editing a message

### 13. Multi-device / Wide-Screen Adaptation
- `common/DeviceAdapt.ets` provides a unified breakpoint system (sm <600vp / md <840vp / lg ≥840vp) plus foldable-state listening; the state is shared globally via AppStorageV2 so any page refreshes automatically when the breakpoint changes
- The host `HomePage` switches between Navigation Stack / Split modes by breakpoint: on wide screens (≥600vp) the sidebar is embedded and persistent on the left with the chat on the right, resizable by dragging (25%~75%) with a native divider; narrow screens keep the drawer
- On wide screens the embedded sidebar reports its selected conversation through `common/ChatBridge.ets` (an AppStorageV2 reactive bus): `selectionVersion` drives ChatPage to load the conversation, while `sidebarRefreshVersion` / `currentConversationId` drive list refresh and highlighting; the chat column is width-limited to 720vp and centered
- `display.foldStatusChange` and `window.windowSizeChange` are observed so foldables switch between split / single-pane in real time

### 14. Cloud Sync — CloudSyncService
- **Scheme A (local RDB as the source of truth + cloud replica)**: the local RDB is the single source of truth; `service/sync/cloud/CloudSyncService.ets` handles full bidirectional sync with AGC Cloud DB; `service/sync/SyncManager.ets` is the sync facade (status code + listener broadcast), and the "Account login" page (AccountSyncPage) shows the status and triggers manual sync
- **Sync flow**: push first (local → cloud: full `upsert` of conversation / message / category) then pull (cloud → local, merged row by row by timestamp); initialization signs in anonymously via AGC Auth to obtain the Authenticated identity and injects it into `cloudCommon`
- **Conflict policy**: last-write-wins — conversation uses `updated_at`, message / category use `created_at` (cloud seconds ×1000 back to ms before comparing with local); deletion is not synced yet (avoids tombstone complexity, planned enhancement)
- **Timestamps**: local milliseconds → cloud seconds (avoids the Cloud DB Integer 32-bit overflow since `Date.now()` is ~1.7e12)
- **Cloud function id-generator**: invoked from the client via `cloud_objects` (generated by the Cloud Objects compiler + `importObject` Proxy) to generate UUIDs through Cloud Functions

## Data Models

| Model           | Description                                                        |
| --------------- | ------------------------------------------------------------------ |
| `Message`       | A single message (@Observed), with thinking / search / generation state, image & file attachments and branch fields |
| `Conversation`  | A conversation, optionally owned by a folder                        |
| `Category`      | Folder/category (@Observed), multi-level nesting + icon color       |

The three cloud tables (`conversation` / `message` / `category`) mirror the local structure — fields map one-to-one, with timestamps stored in seconds.

## Permissions

| Permission                              | Purpose                            |
| --------------------------------------- | ---------------------------------- |
| `ohos.permission.INTERNET`              | Make LLM requests                  |
| `ohos.permission.KEEP_BACKGROUND_RUNNING` | Keep the streaming connection alive in background |
