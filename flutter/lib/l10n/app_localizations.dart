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
