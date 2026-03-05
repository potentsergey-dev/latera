// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Latera';

  @override
  String get buttonStart => 'Начать';

  @override
  String get buttonSave => 'Сохранить';

  @override
  String get buttonSearch => 'Поиск';

  @override
  String get buttonRetry => 'Повторить';

  @override
  String get onboardingTitle => 'Добро пожаловать в Latera';

  @override
  String get onboardingSubtitle =>
      'Ваш интеллектуальный помощник по документам';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get needsAttentionTitle => 'Требуют внимания';

  @override
  String get initializationError => 'Ошибка инициализации';

  @override
  String get onboardingDescription =>
      'Приложение для отслеживания новых файлов в папке.\nВыберите папку, которую хотите наблюдать:';

  @override
  String get onboardingWhatTracksTitle => 'Что отслеживает приложение';

  @override
  String get onboardingWhatTracksItem1 =>
      'Только новые файлы в выбранной папке';

  @override
  String get onboardingWhatTracksItem2 => 'Имена и пути файлов для поиска';

  @override
  String get onboardingWhatTracksItem3 => 'Содержимое обрабатывается локально';

  @override
  String get onboardingPrivacyTitle => 'Конфиденциальность';

  @override
  String get onboardingPrivacyItem1 => 'Данные не покидают ваше устройство';

  @override
  String get onboardingPrivacyItem2 =>
      'Файлы и их содержимое не передаются в интернет';

  @override
  String get onboardingDataStorageTitle => 'Где хранятся данные';

  @override
  String get onboardingIndexLocation => 'Индекс:';

  @override
  String get onboardingSettingsStorage => 'Настройки: локальное хранилище';

  @override
  String get onboardingFolderSectionTitle => 'Папка для наблюдения';

  @override
  String get onboardingSelectFolder => 'Выбрать папку...';

  @override
  String get onboardingUseDefault => 'Использовать по умолчанию';

  @override
  String get onboardingStartButton => 'Начать работу';

  @override
  String get onboardingChangeLater => 'Папку можно изменить позже в настройках';

  @override
  String get onboardingLoading => 'Загрузка...';

  @override
  String onboardingLoadError(String error) {
    return 'Ошибка загрузки: $error';
  }

  @override
  String onboardingFolderPickError(String error) {
    return 'Ошибка выбора папки: $error';
  }

  @override
  String get onboardingDefaultPathUnavailable =>
      'Не удалось получить путь по умолчанию. Выберите папку вручную.';

  @override
  String onboardingSaveError(String error) {
    return 'Ошибка сохранения настроек: $error';
  }

  @override
  String get settingsSectionWatchFolder => 'Папка для наблюдения';

  @override
  String get settingsCurrentPath => 'Текущий путь';

  @override
  String get settingsNotConfigured => 'Не настроена';

  @override
  String get settingsSelectFolder => 'Выбрать папку';

  @override
  String get settingsSelectFolderHint =>
      'Укажите папку для отслеживания новых файлов';

  @override
  String get settingsOpenInExplorer => 'Открыть в проводнике';

  @override
  String get settingsOpenInExplorerHint => 'Открыть папку в файловом менеджере';

  @override
  String get settingsSelectFolderFirst => 'Выберите папку для наблюдения';

  @override
  String get settingsSectionNotifications => 'Уведомления';

  @override
  String get settingsShowNotifications => 'Показывать уведомления';

  @override
  String get settingsShowNotificationsHint =>
      'Уведомления о новых файлах в папке';

  @override
  String get settingsSectionPerformance => 'Производительность';

  @override
  String get settingsResourceSaver => 'Экономия ресурсов';

  @override
  String get settingsResourceSaverOnHint =>
      'Тяжёлые функции отключены, лимиты уменьшены';

  @override
  String get settingsResourceSaverOffHint =>
      'Отключите ресурсоёмкие функции для слабых ПК';

  @override
  String get settingsSectionContentProcessing => 'Обработка содержимого';

  @override
  String get settingsTextExtraction => 'Извлечение текста';

  @override
  String get settingsTextExtractionHint =>
      'Поиск по содержимому PDF, DOCX и др.';

  @override
  String get settingsOcr => 'Распознавание текста (OCR)';

  @override
  String get settingsOcrHint => 'Текст со скриншотов, сканов и фото';

  @override
  String get settingsSemanticSearch => 'Семантический поиск';

  @override
  String get settingsSemanticSearchHint => 'Поиск похожих документов по смыслу';

  @override
  String get settingsTranscription => 'Транскрибация медиа (Whisper)';

  @override
  String get settingsTranscriptionHint => 'Поиск по аудио и видео';

  @override
  String get settingsRag => 'Спроси свою папку (RAG)';

  @override
  String get settingsRagHint => 'Чат с ответами по файлам';

  @override
  String get settingsAutoDescriptions => 'Автоматические описания';

  @override
  String get settingsAutoDescriptionsHint => 'Автосаммари документов';

  @override
  String get settingsAutoTags => 'Автоматические теги';

  @override
  String get settingsAutoTagsHint => 'Автоприсвоение тегов по содержимому';

  @override
  String get settingsComingSoon => 'скоро';

  @override
  String get settingsDisabledByResourceSaver => 'отключено режимом экономии';

  @override
  String get settingsSectionAdvanced => 'Дополнительно';

  @override
  String get settingsResetSettings => 'Сбросить настройки';

  @override
  String get settingsResetHint =>
      'Вернуть все настройки к значениям по умолчанию';

  @override
  String get settingsResetConfirmTitle => 'Сбросить настройки?';

  @override
  String get settingsResetConfirmBody =>
      'Все настройки будут возвращены к значениям по умолчанию. Папка наблюдения будет сброшена.';

  @override
  String get settingsResetDone => 'Настройки сброшены';

  @override
  String get settingsVersion => 'Версия';

  @override
  String settingsFolderChanged(String path) {
    return 'Папка изменена: $path';
  }

  @override
  String settingsFolderPickError(String error) {
    return 'Ошибка выбора папки: $error';
  }

  @override
  String get settingsFolderNotSelected => 'Папка не выбрана';

  @override
  String settingsFolderNotExists(String path) {
    return 'Папка не существует: $path';
  }

  @override
  String get settingsPathDangerousChars => 'Путь содержит недопустимые символы';

  @override
  String settingsOpenFolderError(String error) {
    return 'Ошибка открытия папки: $error';
  }

  @override
  String get settingsLoadError => 'Ошибка загрузки настроек';

  @override
  String get buttonCancel => 'Отмена';

  @override
  String get buttonReset => 'Сбросить';

  @override
  String get trayShowWindow => 'Открыть Latera';

  @override
  String get trayQuit => 'Выход';

  @override
  String get notificationFileNeedsReviewTitle =>
      'Файл добавлен без распознавания';

  @override
  String notificationFileNeedsReviewBody(String fileName) {
    return 'Файл $fileName добавлен без распознавания. Пожалуйста, добавьте описание вручную.';
  }
}
