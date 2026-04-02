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
  String get onboardingCustomFolderProBadge => 'PRO';

  @override
  String get onboardingCustomFolderProHint =>
      'Available in PRO trial — any folder';

  @override
  String get onboardingCustomFolderLockedHint =>
      'Requires PRO — upgrade to use a custom folder';

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
  String get settingsChangeFolderConfirmTitle => 'Change watch folder?';

  @override
  String settingsChangeFolderConfirmBody(String path) {
    return 'Previously indexed files from the current folder will be removed from the search index. They won\'t be deleted from disk.\n\nNew folder: $path';
  }

  @override
  String get settingsChangeFolderConfirmButton => 'Change folder';

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

  @override
  String get settingsSectionLicense => 'License';

  @override
  String get settingsSectionLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Privacy Policy';

  @override
  String get settingsTermsOfUse => 'Terms of Use';

  @override
  String get licenseCurrentMode => 'Current mode: ';

  @override
  String get licenseDescriptionPro =>
      'PRO license active. All features available without restrictions.';

  @override
  String licenseDescriptionTrial(int days) {
    return 'PRO trial period ($days days remaining). All features available. After the trial ends, the app will switch to Basic mode with file limits and restricted features.';
  }

  @override
  String get licenseDescriptionBasic =>
      'Free version with restrictions: file index limit, resource-intensive features disabled (semantic search, auto-descriptions, transcription).';

  @override
  String get licenseHardwareConstraintsTitle => 'Hardware constraints';

  @override
  String get licenseHardwareConstraintsBody =>
      'Less than 6 GB RAM detected. PRO features are unavailable regardless of license status.';

  @override
  String get licenseBuyPro => 'Buy PRO — one-time purchase';

  @override
  String get licensePurchasing => 'Processing...';

  @override
  String get licenseRestorePurchases => 'Restore purchase';

  @override
  String get licenseRestoring => 'Checking...';

  @override
  String get licenseActivatedTitle => 'PRO activated!';

  @override
  String get licenseActivatedBody =>
      'Thank you for your purchase. All PRO features are now available.';

  @override
  String get licenseRestoredTitle => 'Purchase restored!';

  @override
  String get licenseRestoredBody =>
      'PRO version successfully restored. All features are available.';

  @override
  String get licenseRestoreNotFound =>
      'PRO purchase not found in Microsoft Store.';

  @override
  String licenseRestoreError(String error) {
    return 'Error restoring purchase: $error';
  }

  @override
  String get licenseStoreUnavailable =>
      'Microsoft Store is unavailable. Make sure the app was installed from the Store.';

  @override
  String licensePurchaseError(String error) {
    return 'Purchase error: $error';
  }

  @override
  String get trialExpiredCustomFolderBannerTitle => 'PRO trial expired';

  @override
  String get trialExpiredCustomFolderBannerBody =>
      'The custom watch folder is a PRO feature. Your indexed data is preserved. Switch to the default folder or upgrade to PRO to continue.';

  @override
  String get trialExpiredSwitchToDefault => 'Use default folder';

  @override
  String get trialExpiredUpgradePro => 'Upgrade to PRO';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsLanguage => 'Interface language';

  @override
  String get settingsLanguageHint => 'Select the app display language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageRestartHint =>
      'Restart the app to apply the new language';

  @override
  String get onboardingAiModelsTitle => 'AI Models';

  @override
  String get onboardingAiModelsItem1 =>
      'AI models (~1.8 GB) are downloaded on first launch';

  @override
  String get onboardingAiModelsItem2 =>
      'Models are used for semantic search and document summaries';

  @override
  String get onboardingAiModelsItem3 =>
      'Download source: Hugging Face (public repository)';

  @override
  String get onboardingModelsLocation => 'Models:';

  @override
  String get onboardingPrivacyItem3 =>
      'AI models are downloaded once — no ongoing data transfer';

  @override
  String get downloadFailedTitle => 'Download failed';

  @override
  String get downloadFailedEmbedding =>
      'Failed to download the embedding model. Semantic search will not work until the model is downloaded.';

  @override
  String get downloadFailedGguf =>
      'Failed to download the generative model. Summaries, tags, and RAG chat will not work until the model is downloaded.';

  @override
  String get downloadRetryButton => 'Retry download';

  @override
  String downloadSkippedLowRam(int ramMb) {
    return 'Generative AI model skipped: less than 6 GB RAM detected ($ramMb MB). Summaries, tags, and RAG chat are disabled.';
  }

  @override
  String get downloadSkippedLowDisk =>
      'Generative AI model skipped: not enough free disk space (need at least 2 GB). Free up space and restart the app.';

  @override
  String get errorModelNotLoaded =>
      'AI model is not loaded. Please wait for the download to complete or retry in Settings.';

  @override
  String get errorInsufficientRam =>
      'Not enough RAM for this operation. Close other applications and try again.';

  @override
  String get errorInsufficientDisk =>
      'Not enough free disk space. Free up at least 2 GB and try again.';

  @override
  String get errorNetworkUnavailable =>
      'Network connection failed. Check your internet connection and try again.';

  @override
  String get settingsAiModelsStatus => 'AI Models';

  @override
  String get settingsEmbeddingModelReady => 'Embedding model: ready';

  @override
  String get settingsEmbeddingModelMissing => 'Embedding model: not downloaded';

  @override
  String get settingsGgufModelReady => 'Generative model: ready';

  @override
  String get settingsGgufModelMissing => 'Generative model: not downloaded';

  @override
  String get settingsGgufModelSkippedRam =>
      'Generative model: skipped (low RAM)';

  @override
  String get settingsGgufModelSkippedDisk =>
      'Generative model: skipped (low disk space)';

  @override
  String get downloadFailedRetryHint => 'Tap to retry download';

  @override
  String get homeTitle => 'Home';

  @override
  String get homeStatusInitializing => 'Initializing…';

  @override
  String get homeStatusNewFileDetected => 'New file detected';

  @override
  String homeStatusWatchError(String error) {
    return 'Watch error: $error';
  }

  @override
  String get homeStatusFolderChanged => 'Folder changed. Waiting for files…';

  @override
  String get homeStatusReady => 'Ready. Waiting for files…';

  @override
  String homeStatusStartError(String error) {
    return 'Start error: $error';
  }

  @override
  String homeStatusInitError(String error) {
    return 'Initialization error: $error';
  }

  @override
  String get homeFilesInIndex => 'Files in index';

  @override
  String get homeNeedsAttention => 'Need attention';

  @override
  String get homeLastFile => 'Last file';

  @override
  String get homeWatchFolder => 'Watch folder';

  @override
  String get homeNotConfigured => 'Not configured';

  @override
  String homeFileRemovedFromIndex(String fileName) {
    return 'File removed from index: $fileName';
  }

  @override
  String get homeLowRamTitle => 'Insufficient RAM';

  @override
  String get homeLowRamBody =>
      'Less than 6 GB of RAM detected. The app runs in Basic mode with resource-intensive features disabled. For PRO mode and local AI, more RAM is recommended.';
}
