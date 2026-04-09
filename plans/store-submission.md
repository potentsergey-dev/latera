# Microsoft Store Submission — Latera

## App Identity
- **App Name:** Latera
- **Publisher:** Sergey Voronin
- **Identity Name:** com.latera.latera
- **Version:** 1.0.0.0

## Store Listing (English)

### Short Description (max 100 chars)
AI-powered local document search with semantic indexing, RAG, and OCR. Your data stays on your device.

### Description (max 10,000 chars)
Latera is an AI-powered desktop application that indexes and searches your local files using semantic analysis. All data processing happens entirely on your device — no cloud, no tracking.

**Key Features:**
• Full-text search with FTS5 — lightning-fast keyword search (included in Free)
• File watcher — automatically indexes new files in your selected folder (included in Free)
• OCR support — extract text from images and scanned PDFs
• PDF & DOCX text extraction — index office documents automatically
• Multilingual — supports English, Russian, German, Spanish, and Portuguese
• Privacy-first — zero telemetry, zero data collection, zero cloud uploads
• Vulkan GPU acceleration — faster AI inference when available
• Semantic search — find documents by meaning, not just keywords (PRO)
• Local RAG (Retrieval-Augmented Generation) — ask questions about your documents (PRO)
• AI-powered auto-summaries and tags for your files (PRO)

**How It Works:**
1. Select a folder to watch
2. Latera automatically indexes your documents
3. Search by keywords or ask natural language questions
4. Get AI-powered answers grounded in your actual documents

**AI Models:**
Latera downloads compact AI models on first launch (~200 MB total) for semantic embeddings and text generation. Models run entirely locally on your CPU (or GPU with Vulkan support).

**Free Version Includes:**
• Up to 100 indexed files
• Full-text search (FTS5) and file indexing
• TXT, MD, PDF, DOCX support

**Pro Version Unlocks:**
• Unlimited files
• Semantic search & RAG (Ask your folder)
• Extended format support
• Custom watch folder selection

### Keywords
document search, semantic search, local AI, RAG, OCR, file indexer, desktop search, privacy, offline AI, PDF search

### Store Listing (Russian)

#### Краткое описание
ИИ-поиск по документам с семантической индексацией, RAG и OCR. Данные остаются на вашем устройстве.

#### Описание
Latera — настольное приложение для интеллектуального поиска по вашим файлам с использованием ИИ. Вся обработка данных происходит локально — без облака, без слежки, без отправки данных.

**Возможности:**
• Семантический поиск — находите документы по смыслу, а не только по ключевым словам
• Локальный RAG — задавайте вопросы по вашим документам
• Полнотекстовый поиск FTS5 — молниеносный поиск по ключевым словам
• OCR — извлечение текста из изображений и сканов
• Извлечение текста из PDF и DOCX
• Автоматические summary и теги для файлов
• Наблюдение за папкой — автоматическая индексация новых файлов
• Многоязычность — EN, RU, DE, ES, PT
• Конфиденциальность — ноль телеметрии, ноль сбора данных
• Ускорение на GPU через Vulkan

## Category
**Primary:** Productivity
**Secondary:** Utilities & Tools

## Age Rating
**IARC Rating:** Everyone (3+)
- No user-generated content
- No social features
- No in-app purchases of real goods
- No location data
- No personal data collection

## Privacy Policy
URL: https://potentsergey-dev.github.io/latera/privacy

## Terms of Use
URL: https://potentsergey-dev.github.io/latera/terms

## Support Contact
Email: potentsergey@gmail.com

## System Requirements
- **OS:** Windows 10 version 1809 (build 17763) or later
- **Architecture:** x64
- **RAM:** 4 GB minimum, 8 GB recommended
- **Disk:** ~500 MB for app + AI models
- **Internet:** Required only for first-launch model download and license verification

## Capabilities Justification
- **broadFileSystemAccess:** Required for file indexing — the app watches and indexes user-selected folders. Cannot function with per-file picker dialogs as it needs to scan entire directory trees.
- **internetClient:** Required for downloading AI models from Hugging Face on first launch and for Microsoft Store license verification.
- **picturesLibrary:** Enables indexing and OCR of images in the user's Pictures library.

## Screenshots Needed
1. Main search screen with results
2. RAG conversation screen
3. Onboarding / folder selection
4. Settings screen
5. Semantic search results

## WACK Test Checklist
- [ ] Run Windows App Certification Kit
- [ ] All security tests pass
- [ ] All API compliance tests pass
- [ ] Performance tests pass
- [ ] No blocked APIs used

## Publisher Certificate
- [ ] Register in Microsoft Partner Center
- [ ] Reserve app name "Latera"
- [ ] Get Store publisher certificate (CN=...)
- [ ] Update `publisher` in flutter/pubspec.yaml
- [ ] Update publisher in msix_unpack2/AppxManifest.xml
- [ ] Rebuild MSIX with Store certificate
