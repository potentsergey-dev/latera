import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// Application title
  ///
  /// In en, this message translates to:
  /// **'Latera'**
  String get appTitle;

  /// Start button label
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get buttonStart;

  /// Save button label
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get buttonSave;

  /// Search button label
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get buttonSearch;

  /// Retry button label
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get buttonRetry;

  /// Onboarding screen title
  ///
  /// In en, this message translates to:
  /// **'Welcome to Latera'**
  String get onboardingTitle;

  /// Onboarding screen subtitle
  ///
  /// In en, this message translates to:
  /// **'Your intelligent document assistant'**
  String get onboardingSubtitle;

  /// Settings screen title
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Needs Attention section title
  ///
  /// In en, this message translates to:
  /// **'Needs Attention'**
  String get needsAttentionTitle;

  /// Error title shown when app fails to initialize
  ///
  /// In en, this message translates to:
  /// **'Initialization error'**
  String get initializationError;

  /// Onboarding screen description
  ///
  /// In en, this message translates to:
  /// **'App for tracking new files in a folder.\nSelect a folder to watch:'**
  String get onboardingDescription;

  /// Section title: what is monitored
  ///
  /// In en, this message translates to:
  /// **'What the app tracks'**
  String get onboardingWhatTracksTitle;

  /// Tracking info bullet 1
  ///
  /// In en, this message translates to:
  /// **'Only new files in the selected folder'**
  String get onboardingWhatTracksItem1;

  /// Tracking info bullet 2
  ///
  /// In en, this message translates to:
  /// **'File names and paths for search'**
  String get onboardingWhatTracksItem2;

  /// Tracking info bullet 3
  ///
  /// In en, this message translates to:
  /// **'Content is processed locally'**
  String get onboardingWhatTracksItem3;

  /// Section title: privacy
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get onboardingPrivacyTitle;

  /// Privacy bullet 1
  ///
  /// In en, this message translates to:
  /// **'Data does not leave your device'**
  String get onboardingPrivacyItem1;

  /// Privacy bullet 2
  ///
  /// In en, this message translates to:
  /// **'Files and their content are not sent to the internet'**
  String get onboardingPrivacyItem2;

  /// Section title: data storage
  ///
  /// In en, this message translates to:
  /// **'Where data is stored'**
  String get onboardingDataStorageTitle;

  /// Label for index path
  ///
  /// In en, this message translates to:
  /// **'Index:'**
  String get onboardingIndexLocation;

  /// Settings storage info
  ///
  /// In en, this message translates to:
  /// **'Settings: local storage'**
  String get onboardingSettingsStorage;

  /// Section title: folder selection
  ///
  /// In en, this message translates to:
  /// **'Watch folder'**
  String get onboardingFolderSectionTitle;

  /// Button to pick a folder
  ///
  /// In en, this message translates to:
  /// **'Select folder...'**
  String get onboardingSelectFolder;

  /// PRO badge label next to custom folder selector
  ///
  /// In en, this message translates to:
  /// **'PRO'**
  String get onboardingCustomFolderProBadge;

  /// Hint shown on custom folder option during PRO trial
  ///
  /// In en, this message translates to:
  /// **'Available in PRO trial — any folder'**
  String get onboardingCustomFolderProHint;

  /// Hint shown on disabled custom folder option for free users
  ///
  /// In en, this message translates to:
  /// **'Requires PRO — upgrade to use a custom folder'**
  String get onboardingCustomFolderLockedHint;

  /// Use default folder option
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get onboardingUseDefault;

  /// Onboarding accept/start button
  ///
  /// In en, this message translates to:
  /// **'Start working'**
  String get onboardingStartButton;

  /// Hint below the start button
  ///
  /// In en, this message translates to:
  /// **'You can change the folder later in settings'**
  String get onboardingChangeLater;

  /// Generic loading label
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get onboardingLoading;

  /// Error loading default path
  ///
  /// In en, this message translates to:
  /// **'Loading error: {error}'**
  String onboardingLoadError(String error);

  /// Error picking folder
  ///
  /// In en, this message translates to:
  /// **'Error selecting folder: {error}'**
  String onboardingFolderPickError(String error);

  /// Warning when default path fails
  ///
  /// In en, this message translates to:
  /// **'Default path could not be loaded. Please select a folder manually.'**
  String get onboardingDefaultPathUnavailable;

  /// Error saving onboarding config
  ///
  /// In en, this message translates to:
  /// **'Error saving settings: {error}'**
  String onboardingSaveError(String error);

  /// Settings section: watch folder
  ///
  /// In en, this message translates to:
  /// **'Watch folder'**
  String get settingsSectionWatchFolder;

  /// Label for current watch path
  ///
  /// In en, this message translates to:
  /// **'Current path'**
  String get settingsCurrentPath;

  /// Shown when watch folder is not set
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get settingsNotConfigured;

  /// Button to select watch folder
  ///
  /// In en, this message translates to:
  /// **'Select folder'**
  String get settingsSelectFolder;

  /// Subtitle for select folder tile
  ///
  /// In en, this message translates to:
  /// **'Choose a folder to monitor for new files'**
  String get settingsSelectFolderHint;

  /// Open folder in file manager
  ///
  /// In en, this message translates to:
  /// **'Open in Explorer'**
  String get settingsOpenInExplorer;

  /// Subtitle for open folder tile
  ///
  /// In en, this message translates to:
  /// **'Open folder in file manager'**
  String get settingsOpenInExplorerHint;

  /// Hint when no folder is selected
  ///
  /// In en, this message translates to:
  /// **'Select a watch folder first'**
  String get settingsSelectFolderFirst;

  /// Settings section: notifications
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsSectionNotifications;

  /// Toggle label for notifications
  ///
  /// In en, this message translates to:
  /// **'Show notifications'**
  String get settingsShowNotifications;

  /// Subtitle for notifications toggle
  ///
  /// In en, this message translates to:
  /// **'Notifications about new files in folder'**
  String get settingsShowNotificationsHint;

  /// Settings section: performance
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settingsSectionPerformance;

  /// Toggle label for resource saving mode
  ///
  /// In en, this message translates to:
  /// **'Resource saving'**
  String get settingsResourceSaver;

  /// Subtitle when resource saver is ON
  ///
  /// In en, this message translates to:
  /// **'Heavy features disabled, limits reduced'**
  String get settingsResourceSaverOnHint;

  /// Subtitle when resource saver is OFF
  ///
  /// In en, this message translates to:
  /// **'Disable resource-intensive features for low-end PCs'**
  String get settingsResourceSaverOffHint;

  /// Settings section: content processing
  ///
  /// In en, this message translates to:
  /// **'Content processing'**
  String get settingsSectionContentProcessing;

  /// Toggle label for text extraction
  ///
  /// In en, this message translates to:
  /// **'Text extraction'**
  String get settingsTextExtraction;

  /// Subtitle for text extraction toggle
  ///
  /// In en, this message translates to:
  /// **'Search by content of PDF, DOCX and others'**
  String get settingsTextExtractionHint;

  /// Toggle label for OCR
  ///
  /// In en, this message translates to:
  /// **'Text recognition (OCR)'**
  String get settingsOcr;

  /// Subtitle for OCR toggle
  ///
  /// In en, this message translates to:
  /// **'Text from screenshots, scans and photos'**
  String get settingsOcrHint;

  /// Toggle label for semantic search
  ///
  /// In en, this message translates to:
  /// **'Semantic search'**
  String get settingsSemanticSearch;

  /// Subtitle for semantic search toggle
  ///
  /// In en, this message translates to:
  /// **'Find similar documents by meaning'**
  String get settingsSemanticSearchHint;

  /// Toggle label for media transcription
  ///
  /// In en, this message translates to:
  /// **'Media transcription (Whisper)'**
  String get settingsTranscription;

  /// Subtitle for transcription toggle
  ///
  /// In en, this message translates to:
  /// **'Search by audio and video content'**
  String get settingsTranscriptionHint;

  /// Toggle label for RAG
  ///
  /// In en, this message translates to:
  /// **'Ask your folder (RAG)'**
  String get settingsRag;

  /// Subtitle for RAG toggle
  ///
  /// In en, this message translates to:
  /// **'Chat with answers from your files'**
  String get settingsRagHint;

  /// Toggle label for auto descriptions
  ///
  /// In en, this message translates to:
  /// **'Automatic descriptions'**
  String get settingsAutoDescriptions;

  /// Subtitle for auto descriptions toggle
  ///
  /// In en, this message translates to:
  /// **'Auto-summary of documents'**
  String get settingsAutoDescriptionsHint;

  /// Toggle label for auto tags
  ///
  /// In en, this message translates to:
  /// **'Automatic tags'**
  String get settingsAutoTags;

  /// Subtitle for auto tags toggle
  ///
  /// In en, this message translates to:
  /// **'Auto-assign tags by content'**
  String get settingsAutoTagsHint;

  /// Badge label for features not yet available
  ///
  /// In en, this message translates to:
  /// **'soon'**
  String get settingsComingSoon;

  /// Suffix when feature is overridden by resource saver
  ///
  /// In en, this message translates to:
  /// **'disabled by resource saving mode'**
  String get settingsDisabledByResourceSaver;

  /// Hint shown when CPU lacks AVX2 for AI features
  ///
  /// In en, this message translates to:
  /// **'slow mode (no AVX2) — keyword extraction only'**
  String get settingsSlowCpuHint;

  /// Settings section: advanced
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settingsSectionAdvanced;

  /// Button to reset all settings
  ///
  /// In en, this message translates to:
  /// **'Reset settings'**
  String get settingsResetSettings;

  /// Subtitle for reset button
  ///
  /// In en, this message translates to:
  /// **'Return all settings to defaults'**
  String get settingsResetHint;

  /// Reset confirmation dialog title
  ///
  /// In en, this message translates to:
  /// **'Reset settings?'**
  String get settingsResetConfirmTitle;

  /// Reset confirmation dialog body
  ///
  /// In en, this message translates to:
  /// **'All settings will be returned to defaults. The watch folder will be reset.'**
  String get settingsResetConfirmBody;

  /// Snackbar after settings reset
  ///
  /// In en, this message translates to:
  /// **'Settings reset'**
  String get settingsResetDone;

  /// App version label
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get settingsVersion;

  /// Snackbar after folder change
  ///
  /// In en, this message translates to:
  /// **'Folder changed: {path}'**
  String settingsFolderChanged(String path);

  /// Confirmation dialog title when changing watch folder
  ///
  /// In en, this message translates to:
  /// **'Change watch folder?'**
  String get settingsChangeFolderConfirmTitle;

  /// Confirmation dialog body when changing watch folder
  ///
  /// In en, this message translates to:
  /// **'Previously indexed files from the current folder will be removed from the search index. They won\'t be deleted from disk.\n\nNew folder: {path}'**
  String settingsChangeFolderConfirmBody(String path);

  /// Confirmation button in change folder dialog
  ///
  /// In en, this message translates to:
  /// **'Change folder'**
  String get settingsChangeFolderConfirmButton;

  /// Error picking folder
  ///
  /// In en, this message translates to:
  /// **'Error selecting folder: {error}'**
  String settingsFolderPickError(String error);

  /// Error when trying to open unselected folder
  ///
  /// In en, this message translates to:
  /// **'Folder not selected'**
  String get settingsFolderNotSelected;

  /// Error when folder does not exist
  ///
  /// In en, this message translates to:
  /// **'Folder does not exist: {path}'**
  String settingsFolderNotExists(String path);

  /// Error for dangerous path chars
  ///
  /// In en, this message translates to:
  /// **'Path contains invalid characters'**
  String get settingsPathDangerousChars;

  /// Error opening folder
  ///
  /// In en, this message translates to:
  /// **'Error opening folder: {error}'**
  String settingsOpenFolderError(String error);

  /// Error title when settings fail to load
  ///
  /// In en, this message translates to:
  /// **'Error loading settings'**
  String get settingsLoadError;

  /// Cancel button label
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get buttonCancel;

  /// Reset button label
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get buttonReset;

  /// Tray menu: show main window
  ///
  /// In en, this message translates to:
  /// **'Open Latera'**
  String get trayShowWindow;

  /// Tray menu: quit application
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;

  /// Notification title when file could not be parsed
  ///
  /// In en, this message translates to:
  /// **'File added without recognition'**
  String get notificationFileNeedsReviewTitle;

  /// Notification body for unrecognized file
  ///
  /// In en, this message translates to:
  /// **'File {fileName} added without recognition. Please add a description manually.'**
  String notificationFileNeedsReviewBody(String fileName);

  /// Settings section: license
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get settingsSectionLicense;

  /// Settings section: legal information
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get settingsSectionLegal;

  /// Link to privacy policy
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get settingsPrivacyPolicy;

  /// Link to terms of use
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get settingsTermsOfUse;

  /// Label before license badge
  ///
  /// In en, this message translates to:
  /// **'Current mode: '**
  String get licenseCurrentMode;

  /// Description for PRO mode
  ///
  /// In en, this message translates to:
  /// **'PRO license active. All features available without restrictions.'**
  String get licenseDescriptionPro;

  /// Description for trial mode
  ///
  /// In en, this message translates to:
  /// **'PRO trial period ({days} days remaining). All features available. After the trial ends, the app will switch to Basic mode with file limits and restricted features.'**
  String licenseDescriptionTrial(int days);

  /// Description for basic mode
  ///
  /// In en, this message translates to:
  /// **'Free version with restrictions: file index limit, resource-intensive features disabled (semantic search, auto-descriptions, transcription).'**
  String get licenseDescriptionBasic;

  /// Title for hardware constraint notice
  ///
  /// In en, this message translates to:
  /// **'Hardware constraints'**
  String get licenseHardwareConstraintsTitle;

  /// Body for hardware constraint notice
  ///
  /// In en, this message translates to:
  /// **'Less than 6 GB RAM detected. PRO features are unavailable regardless of license status.'**
  String get licenseHardwareConstraintsBody;

  /// Buy PRO button label
  ///
  /// In en, this message translates to:
  /// **'Buy PRO — one-time purchase'**
  String get licenseBuyPro;

  /// Buy button label while purchasing
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get licensePurchasing;

  /// Restore purchases button label
  ///
  /// In en, this message translates to:
  /// **'Restore purchase'**
  String get licenseRestorePurchases;

  /// Restore button label while checking
  ///
  /// In en, this message translates to:
  /// **'Checking...'**
  String get licenseRestoring;

  /// Dialog title after successful purchase
  ///
  /// In en, this message translates to:
  /// **'PRO activated!'**
  String get licenseActivatedTitle;

  /// Dialog body after successful purchase
  ///
  /// In en, this message translates to:
  /// **'Thank you for your purchase. All PRO features are now available.'**
  String get licenseActivatedBody;

  /// Dialog title after successful restore
  ///
  /// In en, this message translates to:
  /// **'Purchase restored!'**
  String get licenseRestoredTitle;

  /// Dialog body after successful restore
  ///
  /// In en, this message translates to:
  /// **'PRO version successfully restored. All features are available.'**
  String get licenseRestoredBody;

  /// Snackbar when restore finds no purchase
  ///
  /// In en, this message translates to:
  /// **'PRO purchase not found in Microsoft Store.'**
  String get licenseRestoreNotFound;

  /// Snackbar on restore error
  ///
  /// In en, this message translates to:
  /// **'Error restoring purchase: {error}'**
  String licenseRestoreError(String error);

  /// Error when Store is not reachable
  ///
  /// In en, this message translates to:
  /// **'Microsoft Store is unavailable. Make sure the app was installed from the Store.'**
  String get licenseStoreUnavailable;

  /// Error during purchase
  ///
  /// In en, this message translates to:
  /// **'Purchase error: {error}'**
  String licensePurchaseError(String error);

  /// Banner title when trial expired and custom folder is in use
  ///
  /// In en, this message translates to:
  /// **'PRO trial expired'**
  String get trialExpiredCustomFolderBannerTitle;

  /// Banner body when trial expired and custom folder is in use
  ///
  /// In en, this message translates to:
  /// **'The custom watch folder is a PRO feature. Your indexed data is preserved. Switch to the default folder or upgrade to PRO to continue.'**
  String get trialExpiredCustomFolderBannerBody;

  /// Action button: switch to default folder after trial expiry
  ///
  /// In en, this message translates to:
  /// **'Use default folder'**
  String get trialExpiredSwitchToDefault;

  /// Action button: upgrade to PRO after trial expiry
  ///
  /// In en, this message translates to:
  /// **'Upgrade to PRO'**
  String get trialExpiredUpgradePro;

  /// Settings section: language
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// Language picker label
  ///
  /// In en, this message translates to:
  /// **'Interface language'**
  String get settingsLanguage;

  /// Language picker hint
  ///
  /// In en, this message translates to:
  /// **'Select the app display language'**
  String get settingsLanguageHint;

  /// Use system locale
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// Section title: AI models
  ///
  /// In en, this message translates to:
  /// **'AI Models'**
  String get onboardingAiModelsTitle;

  /// AI models info bullet 1
  ///
  /// In en, this message translates to:
  /// **'AI models (~1.8 GB) are downloaded on first launch'**
  String get onboardingAiModelsItem1;

  /// AI models info bullet 2
  ///
  /// In en, this message translates to:
  /// **'Models are used for semantic search and document summaries'**
  String get onboardingAiModelsItem2;

  /// AI models info bullet 3
  ///
  /// In en, this message translates to:
  /// **'Download source: Hugging Face (public repository)'**
  String get onboardingAiModelsItem3;

  /// Label for models path
  ///
  /// In en, this message translates to:
  /// **'Models:'**
  String get onboardingModelsLocation;

  /// Privacy bullet 3
  ///
  /// In en, this message translates to:
  /// **'AI models are downloaded once — no ongoing data transfer'**
  String get onboardingPrivacyItem3;

  /// Title shown when model download fails
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailedTitle;

  /// Error detail for embedding model download failure
  ///
  /// In en, this message translates to:
  /// **'Failed to download the embedding model. Semantic search will not work until the model is downloaded.'**
  String get downloadFailedEmbedding;

  /// Error detail for GGUF model download failure
  ///
  /// In en, this message translates to:
  /// **'Failed to download the generative model. Summaries, tags, and RAG chat will not work until the model is downloaded.'**
  String get downloadFailedGguf;

  /// Button to retry failed model download
  ///
  /// In en, this message translates to:
  /// **'Retry download'**
  String get downloadRetryButton;

  /// Info shown when GGUF skipped due to low RAM
  ///
  /// In en, this message translates to:
  /// **'Generative AI model skipped: less than 6 GB RAM detected ({ramMb} MB). Summaries, tags, and RAG chat are disabled.'**
  String downloadSkippedLowRam(int ramMb);

  /// Info shown when GGUF skipped due to low disk
  ///
  /// In en, this message translates to:
  /// **'Generative AI model skipped: not enough free disk space (need at least 2 GB). Free up space and restart the app.'**
  String get downloadSkippedLowDisk;

  /// Error when trying to use a feature that requires a model not yet loaded
  ///
  /// In en, this message translates to:
  /// **'AI model is not loaded. Please wait for the download to complete or retry in Settings.'**
  String get errorModelNotLoaded;

  /// Error when operation fails due to low RAM
  ///
  /// In en, this message translates to:
  /// **'Not enough RAM for this operation. Close other applications and try again.'**
  String get errorInsufficientRam;

  /// Error when disk space is insufficient
  ///
  /// In en, this message translates to:
  /// **'Not enough free disk space. Free up at least 2 GB and try again.'**
  String get errorInsufficientDisk;

  /// Error when network is unavailable
  ///
  /// In en, this message translates to:
  /// **'Network connection failed. Check your internet connection and try again.'**
  String get errorNetworkUnavailable;

  /// Settings section: AI models status
  ///
  /// In en, this message translates to:
  /// **'AI Models'**
  String get settingsAiModelsStatus;

  /// Status when embedding model is available
  ///
  /// In en, this message translates to:
  /// **'Embedding model: ready'**
  String get settingsEmbeddingModelReady;

  /// Status when embedding model is missing
  ///
  /// In en, this message translates to:
  /// **'Embedding model: not downloaded'**
  String get settingsEmbeddingModelMissing;

  /// Status when GGUF model is available
  ///
  /// In en, this message translates to:
  /// **'Generative model: ready'**
  String get settingsGgufModelReady;

  /// Status when GGUF model is missing
  ///
  /// In en, this message translates to:
  /// **'Generative model: not downloaded'**
  String get settingsGgufModelMissing;

  /// Status when GGUF is skipped due to low RAM
  ///
  /// In en, this message translates to:
  /// **'Generative model: skipped (low RAM)'**
  String get settingsGgufModelSkippedRam;

  /// Status when GGUF is skipped due to low disk
  ///
  /// In en, this message translates to:
  /// **'Generative model: skipped (low disk space)'**
  String get settingsGgufModelSkippedDisk;

  /// Hint on a retry tile
  ///
  /// In en, this message translates to:
  /// **'Tap to retry download'**
  String get downloadFailedRetryHint;

  /// Home page title
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get homeTitle;

  /// Status while app initializes
  ///
  /// In en, this message translates to:
  /// **'Initializing…'**
  String get homeStatusInitializing;

  /// Status when a new file is found
  ///
  /// In en, this message translates to:
  /// **'New file detected'**
  String get homeStatusNewFileDetected;

  /// Status on watcher error
  ///
  /// In en, this message translates to:
  /// **'Watch error: {error}'**
  String homeStatusWatchError(String error);

  /// Status after watch folder change
  ///
  /// In en, this message translates to:
  /// **'Folder changed. Waiting for files…'**
  String get homeStatusFolderChanged;

  /// Status when coordinator is running
  ///
  /// In en, this message translates to:
  /// **'Ready. Waiting for files…'**
  String get homeStatusReady;

  /// Status on coordinator start failure
  ///
  /// In en, this message translates to:
  /// **'Start error: {error}'**
  String homeStatusStartError(String error);

  /// Status on init failure
  ///
  /// In en, this message translates to:
  /// **'Initialization error: {error}'**
  String homeStatusInitError(String error);

  /// Card label for indexed file count
  ///
  /// In en, this message translates to:
  /// **'Files in index'**
  String get homeFilesInIndex;

  /// Card label for inbox count
  ///
  /// In en, this message translates to:
  /// **'Need attention'**
  String get homeNeedsAttention;

  /// Card label for last file name
  ///
  /// In en, this message translates to:
  /// **'Last file'**
  String get homeLastFile;

  /// Label for watch folder path
  ///
  /// In en, this message translates to:
  /// **'Watch folder'**
  String get homeWatchFolder;

  /// Shown when watch folder not set
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get homeNotConfigured;

  /// Info bar on file removal
  ///
  /// In en, this message translates to:
  /// **'File removed from index: {fileName}'**
  String homeFileRemovedFromIndex(String fileName);

  /// Low RAM notification title
  ///
  /// In en, this message translates to:
  /// **'Insufficient RAM'**
  String get homeLowRamTitle;

  /// Low RAM notification body
  ///
  /// In en, this message translates to:
  /// **'Less than 6 GB of RAM detected. The app runs in Basic mode with resource-intensive features disabled. For PRO mode and local AI, more RAM is recommended.'**
  String get homeLowRamBody;

  /// Navigation pane: Home tab
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Navigation pane: Search tab
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get navSearch;

  /// Navigation pane: Inbox tab
  ///
  /// In en, this message translates to:
  /// **'Inbox'**
  String get navInbox;

  /// Navigation pane: Settings tab
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Save button label while saving
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get buttonSaving;

  /// Empty state title in inbox
  ///
  /// In en, this message translates to:
  /// **'All files processed'**
  String get inboxAllProcessed;

  /// Empty state hint in inbox
  ///
  /// In en, this message translates to:
  /// **'New files will appear here automatically'**
  String get inboxNewFilesHint;

  /// Hint when no file is selected
  ///
  /// In en, this message translates to:
  /// **'Select a file from the list'**
  String get inboxSelectFile;

  /// Error saving inbox review
  ///
  /// In en, this message translates to:
  /// **'Save error: {error}'**
  String inboxSaveError(String error);

  /// Warning when file is missing
  ///
  /// In en, this message translates to:
  /// **'File not found on disk'**
  String get inboxFileNotFound;

  /// Label for description field
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get inboxDescription;

  /// Placeholder for description field
  ///
  /// In en, this message translates to:
  /// **'Add a file description to improve search…'**
  String get inboxDescriptionPlaceholder;

  /// Label for tags field
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get inboxTags;

  /// Placeholder for tags field
  ///
  /// In en, this message translates to:
  /// **'Enter tags separated by commas…'**
  String get inboxTagsPlaceholder;

  /// Search page header
  ///
  /// In en, this message translates to:
  /// **'File search'**
  String get searchTitle;

  /// Label for semantic search mode
  ///
  /// In en, this message translates to:
  /// **'Semantic'**
  String get searchSemantic;

  /// Label for full-text search mode
  ///
  /// In en, this message translates to:
  /// **'Full-text'**
  String get searchFulltext;

  /// Placeholder for semantic search
  ///
  /// In en, this message translates to:
  /// **'Describe what you\'re looking for…'**
  String get searchSemanticPlaceholder;

  /// Placeholder for full-text search
  ///
  /// In en, this message translates to:
  /// **'Enter keywords…'**
  String get searchKeywordsPlaceholder;

  /// Search field text for similar files
  ///
  /// In en, this message translates to:
  /// **'Similar to: {fileName}'**
  String searchSimilarTo(String fileName);

  /// Warning when file is missing in search
  ///
  /// In en, this message translates to:
  /// **'File not found on disk'**
  String get searchFileNotFound;

  /// Title for search error state
  ///
  /// In en, this message translates to:
  /// **'Search error'**
  String get searchError;

  /// Hint in initial search state
  ///
  /// In en, this message translates to:
  /// **'Enter a search query'**
  String get searchEnterQuery;

  /// Title when search returns no results
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get searchNoResults;

  /// RAG page header
  ///
  /// In en, this message translates to:
  /// **'Ask your folder'**
  String get ragTitle;

  /// RAG input placeholder
  ///
  /// In en, this message translates to:
  /// **'Ask a question about your documents…'**
  String get ragPlaceholder;

  /// Stop button during RAG query
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get ragStop;

  /// Submit RAG query button
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get ragAsk;

  /// Warning banner for slow CPU
  ///
  /// In en, this message translates to:
  /// **'Your CPU does not support fast instructions (AVX2). LLM generation works, but responses may take 1–3 minutes. Use the Stop button to cancel.'**
  String get ragSlowCpuWarning;

  /// Warning when GGUF skipped due to low RAM
  ///
  /// In en, this message translates to:
  /// **'Generative model not loaded: insufficient RAM (need ≥ 6 GB). Answers are formed from found snippets without AI generation.'**
  String get ragLowRamWarning;

  /// Warning when GGUF skipped due to low disk
  ///
  /// In en, this message translates to:
  /// **'Generative model not loaded: not enough disk space (need ≥ 2 GB).'**
  String get ragLowDiskWarning;

  /// Info when model is downloading
  ///
  /// In en, this message translates to:
  /// **'Generative model is downloading…'**
  String get ragModelDownloading;

  /// Warning when model download failed
  ///
  /// In en, this message translates to:
  /// **'Failed to download generative model. Check your internet connection.'**
  String get ragModelFailed;

  /// Default warning when model unavailable
  ///
  /// In en, this message translates to:
  /// **'Generative model not loaded. Answers are formed from found snippets without AI generation.'**
  String get ragModelNotLoaded;

  /// Banner title for slow CPU mode
  ///
  /// In en, this message translates to:
  /// **'Slow mode'**
  String get ragSlowMode;

  /// Banner title for limited (no LLM) mode
  ///
  /// In en, this message translates to:
  /// **'Limited mode'**
  String get ragLimitedMode;

  /// Initial state hint
  ///
  /// In en, this message translates to:
  /// **'Ask a question about your indexed documents'**
  String get ragInitialHint;

  /// Initial state secondary hint
  ///
  /// In en, this message translates to:
  /// **'Search will show relevant snippets from your documents'**
  String get ragInitialSubhint;

  /// Label while LLM is generating
  ///
  /// In en, this message translates to:
  /// **'Generating answer…'**
  String get ragGenerating;

  /// Loading text for slow CPU
  ///
  /// In en, this message translates to:
  /// **'Generating answer (CPU without AVX2, may take 1–3 min)…'**
  String get ragGeneratingSlowCpu;

  /// Loading text for normal query
  ///
  /// In en, this message translates to:
  /// **'Searching for an answer in your documents…'**
  String get ragSearching;

  /// Shown when RAG returns no answer
  ///
  /// In en, this message translates to:
  /// **'Could not find an answer'**
  String get ragNoAnswer;

  /// Label for RAG answer section
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get ragResult;

  /// Label for RAG sources section
  ///
  /// In en, this message translates to:
  /// **'Sources'**
  String get ragSources;

  /// Error when RAG disabled by resource saver
  ///
  /// In en, this message translates to:
  /// **'RAG is disabled in resource saving mode'**
  String get ragDisabledResourceSaver;

  /// Error when RAG disabled in settings
  ///
  /// In en, this message translates to:
  /// **'RAG is disabled in settings'**
  String get ragDisabledSettings;

  /// Relative time: less than a minute ago
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeJustNow;

  /// Relative time: minutes ago
  ///
  /// In en, this message translates to:
  /// **'{count} min ago'**
  String timeMinutesAgo(int count);

  /// Relative time: hours ago
  ///
  /// In en, this message translates to:
  /// **'{count} hr ago'**
  String timeHoursAgo(int count);

  /// Relative time: days ago
  ///
  /// In en, this message translates to:
  /// **'{count} d ago'**
  String timeDaysAgo(int count);

  /// Status bar header when downloading/loading AI model
  ///
  /// In en, this message translates to:
  /// **'Downloading AI model'**
  String get processingStatusBarDownloadingModel;

  /// Status bar header when processing files
  ///
  /// In en, this message translates to:
  /// **'Processing files'**
  String get processingStatusBarProcessingFiles;

  /// Status bar detail when preparing
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get processingStatusBarPreparing;

  /// Status bar detail for GGUF model download
  ///
  /// In en, this message translates to:
  /// **'qwen2.5-3b-instruct-q4_k_m · generative model (~1.7 GB)'**
  String get processingStatusBarGgufModelDetail;

  /// File processing counter
  ///
  /// In en, this message translates to:
  /// **'{completed} of {total}'**
  String processingStatusBarOf(int completed, int total);

  /// Remaining items counter
  ///
  /// In en, this message translates to:
  /// **'{count} remaining'**
  String processingStatusBarRemaining(int count);

  /// Job type label for LLM download
  ///
  /// In en, this message translates to:
  /// **'Downloading AI model…'**
  String get processingJobLlmDownload;

  /// Job type label for GGUF download
  ///
  /// In en, this message translates to:
  /// **'Downloading generative model…'**
  String get processingJobGgufDownload;

  /// Job type label for text extraction
  ///
  /// In en, this message translates to:
  /// **'text extraction'**
  String get processingJobTextExtraction;

  /// Job type label for transcription
  ///
  /// In en, this message translates to:
  /// **'transcription'**
  String get processingJobTranscription;

  /// Job type label for embeddings
  ///
  /// In en, this message translates to:
  /// **'embeddings'**
  String get processingJobEmbeddings;

  /// Job type label for OCR
  ///
  /// In en, this message translates to:
  /// **'text recognition (OCR)'**
  String get processingJobOcr;

  /// Job type label for auto-summary
  ///
  /// In en, this message translates to:
  /// **'auto-description'**
  String get processingJobAutoSummary;

  /// Job type label for auto-tags
  ///
  /// In en, this message translates to:
  /// **'auto-tags'**
  String get processingJobAutoTags;

  /// RAG error when question is empty
  ///
  /// In en, this message translates to:
  /// **'Enter a question'**
  String get ragErrorEmptyQuestion;

  /// RAG error when no relevant chunks found
  ///
  /// In en, this message translates to:
  /// **'No relevant snippets found.\nTry rephrasing your question or index more documents.'**
  String get ragErrorNoChunks;

  /// RAG error on query failure
  ///
  /// In en, this message translates to:
  /// **'Error executing query'**
  String get ragErrorQueryFailed;

  /// RAG error for unknown error code
  ///
  /// In en, this message translates to:
  /// **'Could not get an answer'**
  String get ragErrorUnknown;

  /// Message shown when RAG requires PRO license
  ///
  /// In en, this message translates to:
  /// **'Available in PRO'**
  String get ragProRequired;

  /// Button to learn about PRO in RAG screen
  ///
  /// In en, this message translates to:
  /// **'Learn about PRO'**
  String get ragLearnAboutPro;

  /// Sources section label with count
  ///
  /// In en, this message translates to:
  /// **'Sources ({count})'**
  String ragSourcesCount(int count);

  /// Button to report inappropriate AI-generated content
  ///
  /// In en, this message translates to:
  /// **'Report this answer'**
  String get ragReportContent;

  /// Title of the report dialog
  ///
  /// In en, this message translates to:
  /// **'Report inappropriate AI content'**
  String get ragReportDialogTitle;

  /// Body of the report dialog
  ///
  /// In en, this message translates to:
  /// **'If this AI-generated response contains inappropriate, harmful, or significantly inaccurate content, please let us know.'**
  String get ragReportDialogBody;

  /// Confirm button in the report dialog
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ragReportDialogOk;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
