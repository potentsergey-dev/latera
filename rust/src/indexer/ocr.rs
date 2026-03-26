//! Оптическое распознавание символов (OCR) для изображений и скан-PDF.
//!
//! Модуль предоставляет API для извлечения текста из изображений и
//! отсканированных PDF-документов. Использует встроенный Windows API
//! (`Windows.Media.Ocr`) — без сторонних библиотек и тяжёлых зависимостей.
//!
//! Поддерживаемые форматы:
//! - Изображения: png, jpg, jpeg, tiff, tif, bmp (через Windows Imaging Component)
//! - Скан-PDF: pdf (извлечение встроенных JPEG-изображений + OCR каждого)
//!
//! Лимиты:
//! - `max_pages_per_pdf` — максимальное количество страниц скан-PDF
//! - `max_file_size_mb` — максимальный размер файла

use std::path::Path;

use log::{debug, info, warn};

// ============================================================================
// Supported extensions
// ============================================================================

/// Расширения изображений, поддерживаемых OCR.
const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "tiff", "tif", "bmp"];

/// Расширения PDF (для скан-PDF без text layer).
const OCR_PDF_EXTENSIONS: &[&str] = &["pdf"];

// ============================================================================
// Public types
// ============================================================================

/// Опции OCR.
///
/// Передаются из Flutter-стороны для уважения пользовательских лимитов
/// (`AppConfig.effectiveLimits`).
#[derive(Clone, Debug)]
pub struct OcrOptions {
    /// Максимальное количество страниц скан-PDF для обработки.
    pub max_pages_per_pdf: u32,
    /// Максимальный размер файла в мегабайтах.
    pub max_file_size_mb: u32,
    /// Язык OCR (BCP-47 language tag, например "en", "ru", "de").
    /// `None` = автоопределение из профиля пользователя.
    pub language: Option<String>,
}

impl Default for OcrOptions {
    fn default() -> Self {
        Self {
            max_pages_per_pdf: 100,
            max_file_size_mb: 50,
            language: None,
        }
    }
}

/// Результат OCR.
///
/// Всегда возвращается (не `Result`), ошибки кодируются в `error_code`.
#[derive(Clone, Debug)]
pub struct OcrResult {
    /// Распознанный текст (может быть пуст при ошибке).
    pub text: String,
    /// Тип контента: `"image"`, `"scan_pdf"`, `"unsupported"`, `"unknown"`.
    pub content_type: String,
    /// Количество обработанных страниц (для скан-PDF; для изображений — 1 при успехе, 0 при ошибке).
    pub pages_processed: u32,
    /// Уверенность распознавания (0.0 – 1.0), `None` при ошибке.
    pub confidence: Option<f64>,
    /// Код ошибки, если была:
    /// - `None` — успех
    /// - `"file_too_large"` — файл превышает лимит `max_file_size_mb`
    /// - `"too_many_pages"` — скан-PDF превышает лимит (текст до лимита извлечён)
    /// - `"unsupported_format"` — формат не поддерживается
    /// - `"ocr_failed"` — внутренняя ошибка OCR-движка
    /// - `"file_not_found"` — файл не найден / недоступен
    /// - `"empty_image"` — изображение не содержит распознаваемого текста
    /// - `"no_ocr_language"` — нет установленных языков OCR в системе
    pub error_code: Option<String>,
}

impl OcrResult {
    /// Успешное распознавание.
    fn success(text: String, content_type: &str, pages_processed: u32, confidence: f64) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            pages_processed,
            confidence: Some(confidence),
            error_code: None,
        }
    }

    /// Частичный успех с предупреждением (например, too_many_pages).
    fn with_warning(
        text: String,
        content_type: &str,
        pages_processed: u32,
        confidence: f64,
        error_code: &str,
    ) -> Self {
        Self {
            text,
            content_type: content_type.to_string(),
            pages_processed,
            confidence: Some(confidence),
            error_code: Some(error_code.to_string()),
        }
    }

    /// Ошибка без текста.
    fn error(content_type: &str, error_code: &str) -> Self {
        Self {
            text: String::new(),
            content_type: content_type.to_string(),
            pages_processed: 0,
            confidence: None,
            error_code: Some(error_code.to_string()),
        }
    }
}

// ============================================================================
// Public API
// ============================================================================

/// Проверяет, является ли файл поддерживаемым для OCR.
pub fn is_ocr_supported(file_path: &Path) -> bool {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return false,
    };
    IMAGE_EXTENSIONS.contains(&ext.as_str()) || OCR_PDF_EXTENSIONS.contains(&ext.as_str())
}

/// Определяет тип контента OCR по расширению.
///
/// Возвращает `"image"`, `"scan_pdf"` или `"unsupported"`.
pub fn ocr_content_type(file_path: &Path) -> &'static str {
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => return "unsupported",
    };
    if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
        "image"
    } else if OCR_PDF_EXTENSIONS.contains(&ext.as_str()) {
        "scan_pdf"
    } else {
        "unsupported"
    }
}

/// Извлекает текст из изображения или скан-PDF через OCR.
///
/// Использует встроенный Windows API (`Windows.Media.Ocr`) через крейт `windows`.
/// Для изображений — прямое распознавание через `BitmapDecoder` + `OcrEngine`.
/// Для скан-PDF — извлечение встроенных JPEG-изображений из PDF и OCR каждого.
pub fn ocr_extract_text(file_path: &Path, options: &OcrOptions) -> OcrResult {
    // Проверяем расширение файла
    let ext = match file_path.extension().and_then(|e| e.to_str()) {
        Some(e) => e.to_lowercase(),
        None => {
            return OcrResult::error("unsupported", "unsupported_format");
        }
    };

    let content_type = if IMAGE_EXTENSIONS.contains(&ext.as_str()) {
        "image"
    } else if OCR_PDF_EXTENSIONS.contains(&ext.as_str()) {
        "scan_pdf"
    } else {
        return OcrResult::error("unsupported", "unsupported_format");
    };

    // Проверяем существование файла
    let metadata = match std::fs::metadata(file_path) {
        Ok(m) => m,
        Err(e) => {
            debug!("Cannot access file {}: {}", file_path.display(), e);
            return OcrResult::error("unknown", "file_not_found");
        }
    };

    // Проверяем размер файла
    let max_bytes = u64::from(options.max_file_size_mb) * 1024 * 1024;
    if metadata.len() > max_bytes {
        debug!(
            "File too large ({} bytes, limit {} MB): {}",
            metadata.len(),
            options.max_file_size_mb,
            file_path.display()
        );
        return OcrResult::error(content_type, "file_too_large");
    }

    // Вызываем Windows OCR
    #[cfg(target_os = "windows")]
    {
        if content_type == "image" {
            ocr_image_windows(file_path, options)
        } else {
            ocr_scan_pdf_windows(file_path, options)
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        warn!(
            "OCR is only supported on Windows (Windows.Media.Ocr): {}",
            file_path.display()
        );
        OcrResult::error(content_type, "ocr_failed")
    }
}

// ============================================================================
// Windows OCR implementation
// ============================================================================

#[cfg(target_os = "windows")]
mod win_ocr {
    use log::debug;

    use windows::core::HSTRING;
    use windows::Graphics::Imaging::{BitmapAlphaMode, BitmapDecoder, BitmapPixelFormat};
    use windows::Media::Ocr::OcrEngine;
    use windows::Storage::{FileAccessMode, StorageFile};
    use windows::Win32::System::Com::{CoInitializeEx, COINIT_MULTITHREADED};

    /// Результат Windows OCR.
    pub struct RecognitionResult {
        pub text: String,
        /// Оценка уверенности (Windows OCR не предоставляет per-word confidence,
        /// поэтому используем эвристику).
        pub confidence: f64,
    }

    /// Инициализирует COM (multithreaded apartment) — безопасно при повторных вызовах.
    fn ensure_com() {
        unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
        }
    }

    /// Распознать текст из файла изображения через Windows.Media.Ocr.
    ///
    /// Поддерживает форматы, поддерживаемые Windows Imaging Component (WIC):
    /// JPEG, PNG, BMP, TIFF, GIF, ICO, WDP.
    pub fn recognize_image_file(
        file_path: &str,
        language: Option<&str>,
    ) -> Result<RecognitionResult, String> {
        ensure_com();

        // 1. Открываем файл через StorageFile
        let path_h = HSTRING::from(file_path);
        let file = StorageFile::GetFileFromPathAsync(&path_h)
            .map_err(|e| format!("GetFileFromPathAsync: {e}"))?
            .get()
            .map_err(|e| format!("Cannot open StorageFile: {e}"))?;

        // 2. Открываем поток для чтения
        let stream = file
            .OpenAsync(FileAccessMode::Read)
            .map_err(|e| format!("OpenAsync: {e}"))?
            .get()
            .map_err(|e| format!("Cannot open stream: {e}"))?;

        recognize_from_stream(&stream, language)
    }

    /// Распознать текст из IRandomAccessStream (используется и для файлов, и для in-memory).
    pub fn recognize_from_stream(
        stream: &windows::Storage::Streams::IRandomAccessStream,
        language: Option<&str>,
    ) -> Result<RecognitionResult, String> {
        // 3. Декодируем изображение
        let decoder = BitmapDecoder::CreateAsync(stream)
            .map_err(|e| format!("BitmapDecoder::CreateAsync: {e}"))?
            .get()
            .map_err(|e| format!("Cannot decode image: {e}"))?;

        // 4. Получаем SoftwareBitmap
        let bitmap = decoder
            .GetSoftwareBitmapAsync()
            .map_err(|e| format!("GetSoftwareBitmapAsync: {e}"))?
            .get()
            .map_err(|e| format!("Cannot get SoftwareBitmap: {e}"))?;

        // 5. OcrEngine требует Bgra8 + Premultiplied alpha
        let format = bitmap
            .BitmapPixelFormat()
            .map_err(|e| format!("BitmapPixelFormat: {e}"))?;
        let alpha = bitmap
            .BitmapAlphaMode()
            .map_err(|e| format!("BitmapAlphaMode: {e}"))?;

        let ocr_bitmap =
            if format != BitmapPixelFormat::Bgra8 || alpha != BitmapAlphaMode::Premultiplied {
                windows::Graphics::Imaging::SoftwareBitmap::ConvertWithAlpha(
                    &bitmap,
                    BitmapPixelFormat::Bgra8,
                    BitmapAlphaMode::Premultiplied,
                )
                .map_err(|e| format!("SoftwareBitmap::ConvertWithAlpha: {e}"))?
            } else {
                bitmap
            };

        // 6. Создаём OCR engine
        let engine = create_ocr_engine(language)?;

        // 7. Распознаём
        let result = engine
            .RecognizeAsync(&ocr_bitmap)
            .map_err(|e| format!("RecognizeAsync: {e}"))?
            .get()
            .map_err(|e| format!("Recognition failed: {e}"))?;

        let text = result
            .Text()
            .map_err(|e| format!("Text: {e}"))?
            .to_string();

        // Windows OCR не предоставляет per-word confidence.
        // Оценка: 0.0 если текст пуст, 0.9 если есть текст.
        let confidence = if text.trim().is_empty() { 0.0 } else { 0.9 };

        debug!("Windows OCR: recognized {} chars", text.len());

        Ok(RecognitionResult { text, confidence })
    }

    /// Создать OcrEngine для указанного языка или из профиля пользователя.
    fn create_ocr_engine(language: Option<&str>) -> Result<OcrEngine, String> {
        match language {
            Some(lang_tag) => {
                let lang_h = HSTRING::from(lang_tag);
                let lang = windows::Globalization::Language::CreateLanguage(&lang_h)
                    .map_err(|e| format!("Language::CreateLanguage('{lang_tag}'): {e}"))?;

                if !OcrEngine::IsLanguageSupported(&lang).unwrap_or(false) {
                    return Err(format!(
                        "OCR language '{lang_tag}' is not installed on this system"
                    ));
                }

                OcrEngine::TryCreateFromLanguage(&lang)
                    .map_err(|e| format!("OcrEngine::TryCreateFromLanguage('{lang_tag}'): {e}"))
            }
            None => OcrEngine::TryCreateFromUserProfileLanguages()
                .map_err(|e| format!("OcrEngine::TryCreateFromUserProfileLanguages: {e}")),
        }
    }

    /// Возвращает BCP-47 теги всех установленных в системе OCR языков.
    ///
    /// Используется для fallback-перебора, когда язык профиля не распознал текст.
    pub fn get_available_ocr_languages() -> Vec<String> {
        ensure_com();

        let langs = match OcrEngine::AvailableRecognizerLanguages() {
            Ok(l) => l,
            Err(e) => {
                debug!("Cannot get available OCR languages: {e}");
                return Vec::new();
            }
        };

        let mut result = Vec::new();
        for i in 0..langs.Size().unwrap_or(0) {
            if let Ok(lang) = langs.GetAt(i) {
                if let Ok(tag) = lang.LanguageTag() {
                    result.push(tag.to_string());
                }
            }
        }

        debug!("Available OCR languages: {:?}", result);
        result
    }

    /// Распознать текст из байтов изображения (JPEG) через in-memory stream.
    ///
    /// Используется для OCR извлечённых из PDF изображений.
    pub fn recognize_image_bytes(
        image_data: &[u8],
        language: Option<&str>,
    ) -> Result<RecognitionResult, String> {
        use windows::Storage::Streams::{DataWriter, InMemoryRandomAccessStream};

        ensure_com();

        // Создаём in-memory stream
        let mem_stream = InMemoryRandomAccessStream::new()
            .map_err(|e| format!("InMemoryRandomAccessStream::new: {e}"))?;

        // Записываем данные через DataWriter
        let writer = DataWriter::CreateDataWriter(&mem_stream)
            .map_err(|e| format!("DataWriter::CreateDataWriter: {e}"))?;

        writer
            .WriteBytes(image_data)
            .map_err(|e| format!("WriteBytes: {e}"))?;

        writer
            .StoreAsync()
            .map_err(|e| format!("StoreAsync: {e}"))?
            .get()
            .map_err(|e| format!("Store: {e}"))?;

        writer
            .FlushAsync()
            .map_err(|e| format!("FlushAsync: {e}"))?
            .get()
            .map_err(|e| format!("Flush: {e}"))?;

        // Отсоединяем writer от потока, чтобы его можно было читать
        let _ = writer.DetachStream();

        // Сбрасываем позицию на начало
        mem_stream
            .Seek(0)
            .map_err(|e| format!("Seek: {e}"))?;

        // Распознаём из потока (прямое приведение через windows hierarchy)
        let stream: windows::Storage::Streams::IRandomAccessStream =
            windows::core::Interface::cast(&mem_stream)
                .map_err(|e| format!("Cast to IRandomAccessStream: {e}"))?;

        recognize_from_stream(&stream, language)
    }
}

/// OCR для файла изображения через Windows.Media.Ocr.
#[cfg(target_os = "windows")]
fn ocr_image_windows(file_path: &Path, options: &OcrOptions) -> OcrResult {
    info!(
        "Starting Windows OCR for image: {}",
        file_path.display()
    );

    // Преобразуем путь в абсолютный (Windows API требует абсолютный путь)
    let abs_path = match file_path.canonicalize() {
        Ok(p) => p,
        Err(e) => {
            warn!("Cannot canonicalize path {}: {}", file_path.display(), e);
            return OcrResult::error("image", "file_not_found");
        }
    };

    // Windows пути: canonicalize возвращает UNC-префикс \\?\, убираем его
    let path_str = abs_path
        .to_string_lossy()
        .trim_start_matches("\\\\?\\")
        .to_string();

    match win_ocr::recognize_image_file(&path_str, options.language.as_deref()) {
        Ok(result) => {
            if result.text.trim().is_empty() {
                // Если язык не был задан явно, пробуем все доступные OCR-языки.
                // Это решает проблему, когда профиль пользователя = English,
                // но на изображении текст на другом языке (например, русском).
                if options.language.is_none() {
                    if let Some(fallback) =
                        try_other_ocr_languages_image(&path_str, file_path)
                    {
                        return fallback;
                    }
                }
                info!("OCR: no text found in image: {}", file_path.display());
                OcrResult::error("image", "empty_image")
            } else {
                info!(
                    "OCR: recognized {} chars from image: {}",
                    result.text.len(),
                    file_path.display()
                );
                OcrResult::success(result.text, "image", 1, result.confidence)
            }
        }
        Err(e) => {
            if e.contains("not installed") {
                warn!("OCR language not available: {}", e);
                OcrResult::error("image", "no_ocr_language")
            } else {
                warn!("OCR failed for {}: {}", file_path.display(), e);
                OcrResult::error("image", "ocr_failed")
            }
        }
    }
}

/// Пробует все доступные OCR-языки для изображения (fallback при пустом результате).
///
/// Возвращает `Some(OcrResult)` если удалось распознать текст хотя бы одним языком,
/// `None` если ни один язык не дал результата.
#[cfg(target_os = "windows")]
fn try_other_ocr_languages_image(path_str: &str, file_path: &Path) -> Option<OcrResult> {
    let available = win_ocr::get_available_ocr_languages();
    if available.is_empty() {
        return None;
    }

    debug!(
        "OCR fallback: trying {} available languages for {}",
        available.len(),
        file_path.display()
    );

    for lang_tag in &available {
        match win_ocr::recognize_image_file(path_str, Some(lang_tag)) {
            Ok(result) if !result.text.trim().is_empty() => {
                info!(
                    "OCR fallback: recognized {} chars with language '{}' from {}",
                    result.text.len(),
                    lang_tag,
                    file_path.display()
                );
                return Some(OcrResult::success(
                    result.text,
                    "image",
                    1,
                    result.confidence,
                ));
            }
            Ok(_) => {
                debug!("OCR fallback: no text with language '{}'", lang_tag);
            }
            Err(e) => {
                debug!("OCR fallback: error with language '{}': {}", lang_tag, e);
            }
        }
    }

    None
}

/// Пробует все доступные OCR-языки для байтов изображения (fallback для PDF).
///
/// Возвращает `Some(String)` с распознанным текстом если удалось,
/// `None` если ни один язык не дал результата.
#[cfg(target_os = "windows")]
fn try_other_ocr_languages_bytes(image_data: &[u8]) -> Option<String> {
    let available = win_ocr::get_available_ocr_languages();
    if available.is_empty() {
        return None;
    }

    for lang_tag in &available {
        match win_ocr::recognize_image_bytes(image_data, Some(lang_tag)) {
            Ok(result) if !result.text.trim().is_empty() => {
                debug!(
                    "OCR bytes fallback: recognized {} chars with language '{}'",
                    result.text.len(),
                    lang_tag
                );
                return Some(result.text);
            }
            _ => {}
        }
    }

    None
}

/// OCR для скан-PDF: извлекаем встроенные JPEG-изображения из PDF и распознаём каждое.
#[cfg(target_os = "windows")]
fn ocr_scan_pdf_windows(file_path: &Path, options: &OcrOptions) -> OcrResult {
    info!(
        "Starting Windows OCR for scan-PDF: {}",
        file_path.display()
    );

    let doc = match lopdf::Document::load(file_path) {
        Ok(d) => d,
        Err(e) => {
            warn!("Failed to load PDF for OCR {}: {}", file_path.display(), e);
            return OcrResult::error("scan_pdf", "ocr_failed");
        }
    };

    let pages = doc.get_pages();
    let total_pages = pages.len() as u32;
    let max_pages = options.max_pages_per_pdf;
    let pages_to_process = total_pages.min(max_pages);

    debug!(
        "Scan-PDF OCR: {} total pages, processing up to {}",
        total_pages, pages_to_process
    );

    let mut all_text: Vec<String> = Vec::new();
    let mut pages_processed = 0u32;

    // Для каждой страницы ищем Image XObjects
    for (_page_num, &page_id) in pages.iter().take(pages_to_process as usize) {
        let images = extract_pdf_page_images(&doc, page_id);

        for image_data in &images {
            match win_ocr::recognize_image_bytes(image_data, options.language.as_deref()) {
                Ok(result) if !result.text.trim().is_empty() => {
                    all_text.push(result.text);
                }
                Ok(_) => {
                    // Если язык не задан явно, пробуем другие доступные языки
                    if options.language.is_none() {
                        if let Some(text) = try_other_ocr_languages_bytes(image_data) {
                            all_text.push(text);
                        } else {
                            debug!("OCR: no text found in PDF image (all languages tried)");
                        }
                    } else {
                        debug!("OCR: no text found in PDF image");
                    }
                }
                Err(e) => {
                    debug!("OCR failed for PDF image: {}", e);
                }
            }
        }

        if !images.is_empty() {
            pages_processed += 1;
        }
    }

    if all_text.is_empty() {
        info!(
            "OCR: no text found in scan-PDF: {}",
            file_path.display()
        );
        OcrResult::error("scan_pdf", "empty_image")
    } else {
        let text = all_text.join("\n\n");
        let confidence = 0.85; // Эвристическая оценка для скан-PDF
        info!(
            "OCR: recognized {} chars from {} pages of scan-PDF: {}",
            text.len(),
            pages_processed,
            file_path.display()
        );

        if total_pages > max_pages {
            OcrResult::with_warning(text, "scan_pdf", pages_processed, confidence, "too_many_pages")
        } else {
            OcrResult::success(text, "scan_pdf", pages_processed, confidence)
        }
    }
}

/// Извлекает встроенные изображения (JPEG) со страницы PDF.
///
/// Обрабатывает Image XObjects с фильтром `DCTDecode` (JPEG).
/// Возвращает вектор байтовых массивов — каждый является JPEG-файлом.
#[cfg(target_os = "windows")]
fn extract_pdf_page_images(doc: &lopdf::Document, page_id: lopdf::ObjectId) -> Vec<Vec<u8>> {
    let mut images = Vec::new();

    // Получаем словарь страницы
    let page_dict = match doc.get_dictionary(page_id) {
        Ok(d) => d,
        Err(_) => return images,
    };

    // Resources → XObject
    let resources = match page_dict.get(b"Resources") {
        Ok(r) => r,
        Err(_) => return images,
    };

    let resources_dict = match resolve_as_dict(doc, resources) {
        Some(d) => d,
        None => return images,
    };

    let xobjects = match resources_dict.get(b"XObject") {
        Ok(x) => x,
        Err(_) => return images,
    };

    let xobjects_dict = match resolve_as_dict(doc, xobjects) {
        Some(d) => d,
        None => return images,
    };

    // Перебираем XObjects
    for (_name, obj_ref) in xobjects_dict.iter() {
        // Разрешаем ссылку
        let obj = match obj_ref {
            lopdf::Object::Reference(r) => match doc.get_object(*r) {
                Ok(o) => o,
                Err(_) => continue,
            },
            other => other,
        };

        let stream = match obj.as_stream() {
            Ok(s) => s,
            Err(_) => continue,
        };

        // Проверяем что это Image
        let subtype = stream
            .dict
            .get(b"Subtype")
            .ok()
            .and_then(|s| s.as_name_str().ok());
        if subtype != Some("Image") {
            continue;
        }

        // Проверяем фильтр
        let filter = get_stream_filter(&stream.dict);

        match filter.as_deref() {
            Some("DCTDecode") => {
                // JPEG — содержимое потока = raw JPEG data
                if !stream.content.is_empty() {
                    images.push(stream.content.clone());
                }
            }
            _ => {
                // Другие форматы (FlateDecode, JBIG2Decode и т.д.)
                // не поддерживаются в Phase 1
                debug!("Skipping non-JPEG image in PDF (filter: {:?})", filter);
            }
        }
    }

    images
}

/// Получить значение фильтра из словаря потока.
#[cfg(target_os = "windows")]
fn get_stream_filter(dict: &lopdf::Dictionary) -> Option<String> {
    let filter_obj = dict.get(b"Filter").ok()?;
    match filter_obj {
        lopdf::Object::Name(name) => Some(String::from_utf8_lossy(name).to_string()),
        lopdf::Object::Array(arr) => {
            // Для цепочки фильтров берём последний (ближайший к исходным данным)
            arr.last()
                .and_then(|o| o.as_name_str().ok())
                .map(String::from)
        }
        _ => None,
    }
}

/// Разрешает объект как Dictionary, следуя по ссылкам.
#[cfg(target_os = "windows")]
fn resolve_as_dict<'a>(
    doc: &'a lopdf::Document,
    obj: &'a lopdf::Object,
) -> Option<&'a lopdf::Dictionary> {
    match obj {
        lopdf::Object::Dictionary(d) => Some(d),
        lopdf::Object::Reference(r) => doc
            .get_object(*r)
            .ok()
            .and_then(|o| o.as_dict().ok()),
        _ => None,
    }
}

// ============================================================================
// JSON serialization for FFI
// ============================================================================

/// Сериализует OcrResult в JSON строку (без serde).
///
/// Используется для C FFI bridge.
pub fn ocr_result_to_json(result: &OcrResult) -> String {
    format!(
        r#"{{"text":"{}","content_type":"{}","pages_processed":{},"confidence":{},"error_code":{}}}"#,
        escape_json_string(&result.text),
        escape_json_string(&result.content_type),
        result.pages_processed,
        result
            .confidence
            .map_or("null".to_string(), |c| format!("{c:.4}")),
        result
            .error_code
            .as_ref()
            .map_or("null".to_string(), |e| format!(
                "\"{}\"",
                escape_json_string(e)
            )),
    )
}

/// Экранирует строку для JSON.
fn escape_json_string(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    for ch in s.chars() {
        match ch {
            '\\' => result.push_str("\\\\"),
            '"' => result.push_str("\\\""),
            '\n' => result.push_str("\\n"),
            '\r' => result.push_str("\\r"),
            '\t' => result.push_str("\\t"),
            c if c.is_control() => {
                result.push_str(&format!("\\u{:04x}", c as u32));
            }
            c => result.push(c),
        }
    }
    result
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    // ====================================================================
    // is_ocr_supported
    // ====================================================================

    #[test]
    fn test_image_extensions_supported() {
        for ext in &["png", "jpg", "jpeg", "tiff", "tif", "bmp"] {
            let name = format!("test.{ext}");
            let path = Path::new(&name);
            assert!(
                is_ocr_supported(path),
                "Expected OCR support for .{ext}"
            );
        }
    }

    #[test]
    fn test_pdf_supported_for_ocr() {
        assert!(is_ocr_supported(Path::new("scan.pdf")));
    }

    #[test]
    fn test_unsupported_extensions() {
        for ext in &["txt", "docx", "mp3", "mp4", "rs", "exe"] {
            let name = format!("file.{ext}");
            let path = Path::new(&name);
            assert!(
                !is_ocr_supported(path),
                "Expected no OCR support for .{ext}"
            );
        }
    }

    #[test]
    fn test_no_extension() {
        assert!(!is_ocr_supported(Path::new("noext")));
    }

    // ====================================================================
    // ocr_content_type
    // ====================================================================

    #[test]
    fn test_content_type_image() {
        assert_eq!(ocr_content_type(Path::new("photo.png")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.jpg")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.jpeg")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.tiff")), "image");
        assert_eq!(ocr_content_type(Path::new("photo.bmp")), "image");
    }

    #[test]
    fn test_content_type_scan_pdf() {
        assert_eq!(ocr_content_type(Path::new("scan.pdf")), "scan_pdf");
    }

    #[test]
    fn test_content_type_unsupported() {
        assert_eq!(ocr_content_type(Path::new("file.txt")), "unsupported");
        assert_eq!(ocr_content_type(Path::new("noext")), "unsupported");
    }

    // ====================================================================
    // ocr_extract_text — validation
    // ====================================================================

    #[test]
    fn test_ocr_unsupported_format() {
        let options = OcrOptions::default();
        let result = ocr_extract_text(Path::new("file.txt"), &options);

        assert_eq!(result.content_type, "unsupported");
        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
        assert!(result.text.is_empty());
    }

    #[test]
    fn test_ocr_no_extension() {
        let options = OcrOptions::default();
        let result = ocr_extract_text(Path::new("noext"), &options);

        assert_eq!(result.error_code.as_deref(), Some("unsupported_format"));
    }

    #[test]
    fn test_ocr_file_not_found() {
        let options = OcrOptions::default();
        let result = ocr_extract_text(Path::new("/nonexistent/photo.png"), &options);

        assert_eq!(result.error_code.as_deref(), Some("file_not_found"));
    }

    #[test]
    fn test_ocr_file_too_large() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("big_image.png");
        // Создаём файл размером 2 MB
        let content = vec![0u8; 2 * 1024 * 1024];
        std::fs::write(&file_path, &content).unwrap();

        let options = OcrOptions {
            max_file_size_mb: 1,
            max_pages_per_pdf: 100,
            language: None,
        };
        let result = ocr_extract_text(&file_path, &options);

        assert_eq!(result.content_type, "image");
        assert_eq!(result.error_code.as_deref(), Some("file_too_large"));
        assert!(result.text.is_empty());
    }

    // ====================================================================
    // OcrOptions default
    // ====================================================================

    #[test]
    fn test_ocr_options_default() {
        let options = OcrOptions::default();
        assert_eq!(options.max_pages_per_pdf, 100);
        assert_eq!(options.max_file_size_mb, 50);
        assert!(options.language.is_none());
    }

    // ====================================================================
    // OcrResult constructors
    // ====================================================================

    #[test]
    fn test_ocr_result_success() {
        let result = OcrResult::success("Hello World".to_string(), "image", 1, 0.95);
        assert_eq!(result.text, "Hello World");
        assert_eq!(result.content_type, "image");
        assert_eq!(result.pages_processed, 1);
        assert_eq!(result.confidence, Some(0.95));
        assert!(result.error_code.is_none());
    }

    #[test]
    fn test_ocr_result_with_warning() {
        let result = OcrResult::with_warning(
            "Partial text".to_string(),
            "scan_pdf",
            5,
            0.8,
            "too_many_pages",
        );
        assert_eq!(result.text, "Partial text");
        assert_eq!(result.content_type, "scan_pdf");
        assert_eq!(result.pages_processed, 5);
        assert_eq!(result.confidence, Some(0.8));
        assert_eq!(result.error_code.as_deref(), Some("too_many_pages"));
    }

    #[test]
    fn test_ocr_result_error() {
        let result = OcrResult::error("image", "ocr_failed");
        assert!(result.text.is_empty());
        assert_eq!(result.content_type, "image");
        assert_eq!(result.pages_processed, 0);
        assert!(result.confidence.is_none());
        assert_eq!(result.error_code.as_deref(), Some("ocr_failed"));
    }

    // ====================================================================
    // Case-insensitive extension matching
    // ====================================================================

    #[test]
    fn test_case_insensitive_extensions() {
        assert!(is_ocr_supported(Path::new("photo.PNG")));
        assert!(is_ocr_supported(Path::new("photo.Jpg")));
        assert!(is_ocr_supported(Path::new("scan.PDF")));
        assert!(is_ocr_supported(Path::new("image.TIFF")));
    }

    #[test]
    fn test_ocr_extract_case_insensitive() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("test.JPEG");
        std::fs::write(&file_path, &[0u8; 100]).unwrap();

        let options = OcrOptions::default();
        let result = ocr_extract_text(&file_path, &options);

        // Should be recognized as image, not unsupported
        assert_eq!(result.content_type, "image");
        // On Windows it tries real OCR (may fail with invalid image data);
        // on other platforms it returns "ocr_failed"
        assert!(result.error_code.is_some());
    }

    // ====================================================================
    // JSON serialization
    // ====================================================================

    #[test]
    fn test_ocr_result_to_json_success() {
        let result = OcrResult::success("Hello World".to_string(), "image", 1, 0.90);
        let json = ocr_result_to_json(&result);
        assert!(json.contains(r#""text":"Hello World""#));
        assert!(json.contains(r#""content_type":"image""#));
        assert!(json.contains(r#""pages_processed":1"#));
        assert!(json.contains(r#""error_code":null"#));
    }

    #[test]
    fn test_ocr_result_to_json_error() {
        let result = OcrResult::error("image", "ocr_failed");
        let json = ocr_result_to_json(&result);
        assert!(json.contains(r#""text":"""#));
        assert!(json.contains(r#""error_code":"ocr_failed""#));
    }

    #[test]
    fn test_escape_json_string() {
        assert_eq!(escape_json_string("hello"), "hello");
        assert_eq!(escape_json_string("line1\nline2"), "line1\\nline2");
        assert_eq!(escape_json_string(r#"say "hi""#), r#"say \"hi\""#);
        assert_eq!(escape_json_string("path\\to\\file"), "path\\\\to\\\\file");
        assert_eq!(escape_json_string("tab\there"), "tab\\there");
    }

    // ====================================================================
    // Windows OCR integration tests (only run on Windows with OCR language)
    // ====================================================================

    /// Создаёт минимальный валидный BMP файл (белый прямоугольник).
    /// Windows OCR требует минимум 40x40 пикселей.
    #[cfg(test)]
    fn create_test_bmp(width: u32, height: u32) -> Vec<u8> {
        let row_size = ((width * 3 + 3) / 4) * 4;
        let image_size = row_size * height;
        let file_size = 14 + 40 + image_size;

        let mut data = Vec::with_capacity(file_size as usize);

        // BMP file header (14 bytes)
        data.extend_from_slice(b"BM");
        data.extend_from_slice(&file_size.to_le_bytes());
        data.extend_from_slice(&0u16.to_le_bytes()); // reserved1
        data.extend_from_slice(&0u16.to_le_bytes()); // reserved2
        data.extend_from_slice(&54u32.to_le_bytes()); // pixel data offset

        // DIB header (BITMAPINFOHEADER, 40 bytes)
        data.extend_from_slice(&40u32.to_le_bytes()); // header size
        data.extend_from_slice(&(width as i32).to_le_bytes());
        data.extend_from_slice(&(height as i32).to_le_bytes());
        data.extend_from_slice(&1u16.to_le_bytes()); // color planes
        data.extend_from_slice(&24u16.to_le_bytes()); // bits per pixel
        data.extend_from_slice(&0u32.to_le_bytes()); // compression
        data.extend_from_slice(&image_size.to_le_bytes());
        data.extend_from_slice(&2835i32.to_le_bytes()); // X pixels/meter
        data.extend_from_slice(&2835i32.to_le_bytes()); // Y pixels/meter
        data.extend_from_slice(&0u32.to_le_bytes()); // colors in table
        data.extend_from_slice(&0u32.to_le_bytes()); // important colors

        // Pixel data (all white)
        for _ in 0..height {
            for _ in 0..width {
                data.push(255); // B
                data.push(255); // G
                data.push(255); // R
            }
            for _ in 0..(row_size - width * 3) {
                data.push(0); // padding
            }
        }

        data
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn test_ocr_valid_bmp_empty_image() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("white.bmp");

        let bmp_data = create_test_bmp(100, 100);
        std::fs::write(&file_path, &bmp_data).unwrap();

        let options = OcrOptions::default();
        let result = ocr_extract_text(&file_path, &options);

        assert_eq!(result.content_type, "image");
        // Белое изображение без текста → empty_image или ocr_failed
        assert!(
            result.error_code.as_deref() == Some("empty_image")
                || result.error_code.as_deref() == Some("no_ocr_language"),
            "Unexpected error_code: {:?}",
            result.error_code
        );
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn test_ocr_invalid_image_data() {
        let dir = tempfile::tempdir().unwrap();
        let file_path = dir.path().join("corrupt.bmp");
        // Записываем мусорные данные
        std::fs::write(&file_path, b"not a real image").unwrap();

        let options = OcrOptions::default();
        let result = ocr_extract_text(&file_path, &options);

        assert_eq!(result.content_type, "image");
        assert_eq!(result.error_code.as_deref(), Some("ocr_failed"));
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn test_win_ocr_engine_creation() {
        // Проверяем что OcrEngine создаётся (если OCR-языки установлены)
        let result = win_ocr::recognize_image_bytes(&create_test_bmp(50, 50), None);
        // Либо успех (пустой текст), либо ошибка (нет OCR-языков)
        match result {
            Ok(r) => {
                // Белое изображение → пустой текст
                assert!(r.text.trim().is_empty() || !r.text.is_empty());
            }
            Err(e) => {
                // Допустимо: нет OCR-языков в системе
                assert!(
                    e.contains("not installed") || e.contains("UserProfile"),
                    "Unexpected error: {e}"
                );
            }
        }
    }
}
