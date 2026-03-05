// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Latera';

  @override
  String get buttonStart => 'Start';

  @override
  String get buttonSave => 'Save';

  @override
  String get buttonSearch => 'Search';

  @override
  String get buttonRetry => 'Retry';

  @override
  String get onboardingTitle => 'Welcome to Latera';

  @override
  String get onboardingSubtitle => 'Your intelligent document assistant';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get needsAttentionTitle => 'Needs Attention';

  @override
  String get initializationError => 'Initialization error';

  @override
  String get onboardingDescription =>
      'App for tracking new files in a folder.\nSelect a folder to watch:';

  @override
  String get onboardingWhatTracksTitle => 'What the app tracks';

  @override
  String get onboardingWhatTracksItem1 =>
      'Only new files in the selected folder';

  @override
  String get onboardingWhatTracksItem2 => 'File names and paths for search';

  @override
  String get onboardingWhatTracksItem3 => 'Content is processed locally';

  @override
  String get onboardingPrivacyTitle => 'Privacy';

  @override
  String get onboardingPrivacyItem1 => 'Data does not leave your device';

  @override
  String get onboardingPrivacyItem2 =>
      'Files and their content are not sent to the internet';

  @override
  String get onboardingDataStorageTitle => 'Where data is stored';

  @override
  String get onboardingIndexLocation => 'Index:';

  @override
  String get onboardingSettingsStorage => 'Settings: local storage';

  @override
  String get onboardingFolderSectionTitle => 'Watch folder';

  @override
  String get onboardingSelectFolder => 'Select folder...';

  @override
  String get onboardingUseDefault => 'Use default';

  @override
  String get onboardingStartButton => 'Start working';

  @override
  String get onboardingChangeLater =>
      'You can change the folder later in settings';

  @override
  String get onboardingLoading => 'Loading...';

  @override
  String onboardingLoadError(String error) {
    return 'Loading error: $error';
  }

  @override
  String onboardingFolderPickError(String error) {
    return 'Error selecting folder: $error';
  }

  @override
  String get onboardingDefaultPathUnavailable =>
      'Default path could not be loaded. Please select a folder manually.';

  @override
  String onboardingSaveError(String error) {
    return 'Error saving settings: $error';
  }

  @override
  String get settingsSectionWatchFolder => 'Watch folder';

  @override
  String get settingsCurrentPath => 'Current path';

  @override
  String get settingsNotConfigured => 'Not configured';

  @override
  String get settingsSelectFolder => 'Select folder';

  @override
  String get settingsSelectFolderHint =>
      'Choose a folder to monitor for new files';

  @override
  String get settingsOpenInExplorer => 'Open in Explorer';

  @override
  String get settingsOpenInExplorerHint => 'Open folder in file manager';

  @override
  String get settingsSelectFolderFirst => 'Select a watch folder first';

  @override
  String get settingsSectionNotifications => 'Notifications';

  @override
  String get settingsShowNotifications => 'Show notifications';

  @override
  String get settingsShowNotificationsHint =>
      'Notifications about new files in folder';

  @override
  String get settingsSectionPerformance => 'Performance';

  @override
  String get settingsResourceSaver => 'Resource saving';

  @override
  String get settingsResourceSaverOnHint =>
      'Heavy features disabled, limits reduced';

  @override
  String get settingsResourceSaverOffHint =>
      'Disable resource-intensive features for low-end PCs';

  @override
  String get settingsSectionContentProcessing => 'Content processing';

  @override
  String get settingsTextExtraction => 'Text extraction';

  @override
  String get settingsTextExtractionHint =>
      'Search by content of PDF, DOCX and others';

  @override
  String get settingsOcr => 'Text recognition (OCR)';

  @override
  String get settingsOcrHint => 'Text from screenshots, scans and photos';

  @override
  String get settingsSemanticSearch => 'Semantic search';

  @override
  String get settingsSemanticSearchHint => 'Find similar documents by meaning';

  @override
  String get settingsTranscription => 'Media transcription (Whisper)';

  @override
  String get settingsTranscriptionHint => 'Search by audio and video content';

  @override
  String get settingsRag => 'Ask your folder (RAG)';

  @override
  String get settingsRagHint => 'Chat with answers from your files';

  @override
  String get settingsAutoDescriptions => 'Automatic descriptions';

  @override
  String get settingsAutoDescriptionsHint => 'Auto-summary of documents';

  @override
  String get settingsAutoTags => 'Automatic tags';

  @override
  String get settingsAutoTagsHint => 'Auto-assign tags by content';

  @override
  String get settingsComingSoon => 'soon';

  @override
  String get settingsDisabledByResourceSaver =>
      'disabled by resource saving mode';

  @override
  String get settingsSectionAdvanced => 'Advanced';

  @override
  String get settingsResetSettings => 'Reset settings';

  @override
  String get settingsResetHint => 'Return all settings to defaults';

  @override
  String get settingsResetConfirmTitle => 'Reset settings?';

  @override
  String get settingsResetConfirmBody =>
      'All settings will be returned to defaults. The watch folder will be reset.';

  @override
  String get settingsResetDone => 'Settings reset';

  @override
  String get settingsVersion => 'Version';

  @override
  String settingsFolderChanged(String path) {
    return 'Folder changed: $path';
  }

  @override
  String settingsFolderPickError(String error) {
    return 'Error selecting folder: $error';
  }

  @override
  String get settingsFolderNotSelected => 'Folder not selected';

  @override
  String settingsFolderNotExists(String path) {
    return 'Folder does not exist: $path';
  }

  @override
  String get settingsPathDangerousChars => 'Path contains invalid characters';

  @override
  String settingsOpenFolderError(String error) {
    return 'Error opening folder: $error';
  }

  @override
  String get settingsLoadError => 'Error loading settings';

  @override
  String get buttonCancel => 'Cancel';

  @override
  String get buttonReset => 'Reset';

  @override
  String get trayShowWindow => 'Open Latera';

  @override
  String get trayQuit => 'Quit';

  @override
  String get notificationFileNeedsReviewTitle =>
      'File added without recognition';

  @override
  String notificationFileNeedsReviewBody(String fileName) {
    return 'File $fileName added without recognition. Please add a description manually.';
  }
}
