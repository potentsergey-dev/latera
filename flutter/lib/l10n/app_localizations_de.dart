// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Latera';

  @override
  String get buttonStart => 'Starten';

  @override
  String get buttonSave => 'Speichern';

  @override
  String get buttonSearch => 'Suchen';

  @override
  String get buttonRetry => 'Erneut versuchen';

  @override
  String get onboardingTitle => 'Willkommen bei Latera';

  @override
  String get onboardingSubtitle => 'Ihr intelligenter Dokumenten-Assistent';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get needsAttentionTitle => 'Erfordert Aufmerksamkeit';

  @override
  String get initializationError => 'Initialisierungsfehler';

  @override
  String get onboardingDescription =>
      'App zur Überwachung neuer Dateien in einem Ordner.\nWählen Sie einen Ordner zur Überwachung:';

  @override
  String get onboardingWhatTracksTitle => 'Was die App verfolgt';

  @override
  String get onboardingWhatTracksItem1 =>
      'Nur neue Dateien im ausgewählten Ordner';

  @override
  String get onboardingWhatTracksItem2 => 'Dateinamen und Pfade für die Suche';

  @override
  String get onboardingWhatTracksItem3 => 'Inhalte werden lokal verarbeitet';

  @override
  String get onboardingPrivacyTitle => 'Datenschutz';

  @override
  String get onboardingPrivacyItem1 => 'Daten verlassen Ihr Gerät nicht';

  @override
  String get onboardingPrivacyItem2 =>
      'Dateien und deren Inhalte werden nicht ins Internet gesendet';

  @override
  String get onboardingDataStorageTitle => 'Wo Daten gespeichert werden';

  @override
  String get onboardingIndexLocation => 'Index:';

  @override
  String get onboardingSettingsStorage => 'Einstellungen: lokaler Speicher';

  @override
  String get onboardingFolderSectionTitle => 'Überwachungsordner';

  @override
  String get onboardingSelectFolder => 'Ordner auswählen...';

  @override
  String get onboardingCustomFolderProBadge => 'PRO';

  @override
  String get onboardingCustomFolderProHint =>
      'Verfügbar in der PRO-Testversion — beliebiger Ordner';

  @override
  String get onboardingCustomFolderLockedHint =>
      'Erfordert PRO — Upgrade für benutzerdefinierten Ordner';

  @override
  String get onboardingUseDefault => 'Standard verwenden';

  @override
  String get onboardingStartButton => 'Loslegen';

  @override
  String get onboardingChangeLater =>
      'Sie können den Ordner später in den Einstellungen ändern';

  @override
  String get onboardingLoading => 'Laden...';

  @override
  String onboardingLoadError(String error) {
    return 'Ladefehler: $error';
  }

  @override
  String onboardingFolderPickError(String error) {
    return 'Fehler bei der Ordnerauswahl: $error';
  }

  @override
  String get onboardingDefaultPathUnavailable =>
      'Standardpfad konnte nicht geladen werden. Bitte wählen Sie einen Ordner manuell aus.';

  @override
  String onboardingSaveError(String error) {
    return 'Fehler beim Speichern der Einstellungen: $error';
  }

  @override
  String get settingsSectionWatchFolder => 'Überwachungsordner';

  @override
  String get settingsCurrentPath => 'Aktueller Pfad';

  @override
  String get settingsNotConfigured => 'Nicht konfiguriert';

  @override
  String get settingsSelectFolder => 'Ordner auswählen';

  @override
  String get settingsSelectFolderHint =>
      'Wählen Sie einen Ordner zur Überwachung neuer Dateien';

  @override
  String get settingsOpenInExplorer => 'Im Explorer öffnen';

  @override
  String get settingsOpenInExplorerHint => 'Ordner im Dateimanager öffnen';

  @override
  String get settingsSelectFolderFirst =>
      'Wählen Sie zuerst einen Überwachungsordner';

  @override
  String get settingsSectionNotifications => 'Benachrichtigungen';

  @override
  String get settingsShowNotifications => 'Benachrichtigungen anzeigen';

  @override
  String get settingsShowNotificationsHint =>
      'Benachrichtigungen über neue Dateien im Ordner';

  @override
  String get settingsSectionPerformance => 'Leistung';

  @override
  String get settingsResourceSaver => 'Ressourcenschonung';

  @override
  String get settingsResourceSaverOnHint =>
      'Ressourcenintensive Funktionen deaktiviert, Limits reduziert';

  @override
  String get settingsResourceSaverOffHint =>
      'Ressourcenintensive Funktionen für schwache PCs deaktivieren';

  @override
  String get settingsSectionContentProcessing => 'Inhaltsverarbeitung';

  @override
  String get settingsTextExtraction => 'Textextraktion';

  @override
  String get settingsTextExtractionHint =>
      'Suche nach Inhalten von PDF, DOCX und anderen';

  @override
  String get settingsOcr => 'Texterkennung (OCR)';

  @override
  String get settingsOcrHint => 'Text aus Screenshots, Scans und Fotos';

  @override
  String get settingsSemanticSearch => 'Semantische Suche';

  @override
  String get settingsSemanticSearchHint =>
      'Ähnliche Dokumente nach Bedeutung finden';

  @override
  String get settingsTranscription => 'Medientranskription (Whisper)';

  @override
  String get settingsTranscriptionHint => 'Suche nach Audio- und Videoinhalten';

  @override
  String get settingsRag => 'Ordner befragen (RAG)';

  @override
  String get settingsRagHint => 'Chat mit Antworten aus Ihren Dateien';

  @override
  String get settingsAutoDescriptions => 'Automatische Beschreibungen';

  @override
  String get settingsAutoDescriptionsHint =>
      'Automatische Zusammenfassung von Dokumenten';

  @override
  String get settingsAutoTags => 'Automatische Tags';

  @override
  String get settingsAutoTagsHint => 'Automatische Tag-Zuweisung nach Inhalt';

  @override
  String get settingsComingSoon => 'bald';

  @override
  String get settingsDisabledByResourceSaver =>
      'durch Ressourcenschonung deaktiviert';

  @override
  String get settingsSectionAdvanced => 'Erweitert';

  @override
  String get settingsResetSettings => 'Einstellungen zurücksetzen';

  @override
  String get settingsResetHint =>
      'Alle Einstellungen auf Standardwerte zurücksetzen';

  @override
  String get settingsResetConfirmTitle => 'Einstellungen zurücksetzen?';

  @override
  String get settingsResetConfirmBody =>
      'Alle Einstellungen werden auf Standardwerte zurückgesetzt. Der Überwachungsordner wird zurückgesetzt.';

  @override
  String get settingsResetDone => 'Einstellungen zurückgesetzt';

  @override
  String get settingsVersion => 'Version';

  @override
  String settingsFolderChanged(String path) {
    return 'Ordner geändert: $path';
  }

  @override
  String get settingsChangeFolderConfirmTitle => 'Überwachungsordner ändern?';

  @override
  String settingsChangeFolderConfirmBody(String path) {
    return 'Zuvor indexierte Dateien aus dem aktuellen Ordner werden aus dem Suchindex entfernt. Sie werden nicht von der Festplatte gelöscht.\n\nNeuer Ordner: $path';
  }

  @override
  String get settingsChangeFolderConfirmButton => 'Ordner ändern';

  @override
  String settingsFolderPickError(String error) {
    return 'Fehler bei der Ordnerauswahl: $error';
  }

  @override
  String get settingsFolderNotSelected => 'Kein Ordner ausgewählt';

  @override
  String settingsFolderNotExists(String path) {
    return 'Ordner existiert nicht: $path';
  }

  @override
  String get settingsPathDangerousChars => 'Pfad enthält ungültige Zeichen';

  @override
  String settingsOpenFolderError(String error) {
    return 'Fehler beim Öffnen des Ordners: $error';
  }

  @override
  String get settingsLoadError => 'Fehler beim Laden der Einstellungen';

  @override
  String get buttonCancel => 'Abbrechen';

  @override
  String get buttonReset => 'Zurücksetzen';

  @override
  String get trayShowWindow => 'Latera öffnen';

  @override
  String get trayQuit => 'Beenden';

  @override
  String get notificationFileNeedsReviewTitle =>
      'Datei ohne Erkennung hinzugefügt';

  @override
  String notificationFileNeedsReviewBody(String fileName) {
    return 'Datei $fileName ohne Erkennung hinzugefügt. Bitte fügen Sie manuell eine Beschreibung hinzu.';
  }

  @override
  String get settingsSectionLicense => 'Lizenz';

  @override
  String get settingsSectionLegal => 'Rechtliches';

  @override
  String get settingsPrivacyPolicy => 'Datenschutzrichtlinie';

  @override
  String get settingsTermsOfUse => 'Nutzungsbedingungen';

  @override
  String get licenseCurrentMode => 'Aktueller Modus: ';

  @override
  String get licenseDescriptionPro =>
      'PRO-Lizenz aktiv. Alle Funktionen ohne Einschränkungen verfügbar.';

  @override
  String licenseDescriptionTrial(int days) {
    return 'PRO-Testphase ($days Tage verbleibend). Alle Funktionen verfügbar. Nach Ablauf wechselt die App in den Basic-Modus mit Dateilimits und eingeschränkten Funktionen.';
  }

  @override
  String get licenseDescriptionBasic =>
      'Kostenlose Version mit Einschränkungen: Dateiindexlimit, ressourcenintensive Funktionen deaktiviert (semantische Suche, automatische Beschreibungen, Transkription).';

  @override
  String get licenseHardwareConstraintsTitle => 'Hardwarebeschränkungen';

  @override
  String get licenseHardwareConstraintsBody =>
      'Weniger als 6 GB RAM erkannt. PRO-Funktionen sind unabhängig vom Lizenzstatus nicht verfügbar.';

  @override
  String get licenseBuyPro => 'PRO kaufen — Einmalkauf';

  @override
  String get licensePurchasing => 'Wird verarbeitet...';

  @override
  String get licenseRestorePurchases => 'Kauf wiederherstellen';

  @override
  String get licenseRestoring => 'Wird überprüft...';

  @override
  String get licenseActivatedTitle => 'PRO aktiviert!';

  @override
  String get licenseActivatedBody =>
      'Vielen Dank für Ihren Kauf. Alle PRO-Funktionen sind jetzt verfügbar.';

  @override
  String get licenseRestoredTitle => 'Kauf wiederhergestellt!';

  @override
  String get licenseRestoredBody =>
      'PRO-Version erfolgreich wiederhergestellt. Alle Funktionen sind verfügbar.';

  @override
  String get licenseRestoreNotFound =>
      'PRO-Kauf im Microsoft Store nicht gefunden.';

  @override
  String licenseRestoreError(String error) {
    return 'Fehler beim Wiederherstellen des Kaufs: $error';
  }

  @override
  String get licenseStoreUnavailable =>
      'Microsoft Store nicht verfügbar. Stellen Sie sicher, dass die App aus dem Store installiert wurde.';

  @override
  String licensePurchaseError(String error) {
    return 'Kauffehler: $error';
  }

  @override
  String get trialExpiredCustomFolderBannerTitle => 'PRO-Testphase abgelaufen';

  @override
  String get trialExpiredCustomFolderBannerBody =>
      'Der benutzerdefinierte Überwachungsordner ist eine PRO-Funktion. Ihre indexierten Daten bleiben erhalten. Wechseln Sie zum Standardordner oder upgraden Sie auf PRO, um fortzufahren.';

  @override
  String get trialExpiredSwitchToDefault => 'Standardordner verwenden';

  @override
  String get trialExpiredUpgradePro => 'Auf PRO upgraden';

  @override
  String get settingsSectionLanguage => 'Sprache';

  @override
  String get settingsLanguage => 'Oberflächensprache';

  @override
  String get settingsLanguageHint => 'Anzeigesprache der App auswählen';

  @override
  String get settingsLanguageSystem => 'Systemstandard';

  @override
  String get settingsLanguageRestartHint =>
      'Starten Sie die App neu, um die neue Sprache anzuwenden';

  @override
  String get onboardingAiModelsTitle => 'KI-Modelle';

  @override
  String get onboardingAiModelsItem1 =>
      'KI-Modelle (~1,8 GB) werden beim ersten Start heruntergeladen';

  @override
  String get onboardingAiModelsItem2 =>
      'Modelle werden für semantische Suche und Dokumentzusammenfassungen verwendet';

  @override
  String get onboardingAiModelsItem3 =>
      'Download-Quelle: Hugging Face (öffentliches Repository)';

  @override
  String get onboardingModelsLocation => 'Modelle:';

  @override
  String get onboardingPrivacyItem3 =>
      'KI-Modelle werden einmalig heruntergeladen — kein dauerhafter Datentransfer';

  @override
  String get downloadFailedTitle => 'Download fehlgeschlagen';

  @override
  String get downloadFailedEmbedding =>
      'Das Embedding-Modell konnte nicht heruntergeladen werden. Die semantische Suche funktioniert erst nach dem Download.';

  @override
  String get downloadFailedGguf =>
      'Das generative Modell konnte nicht heruntergeladen werden. Zusammenfassungen, Tags und RAG-Chat funktionieren erst nach dem Download.';

  @override
  String get downloadRetryButton => 'Download wiederholen';

  @override
  String downloadSkippedLowRam(int ramMb) {
    return 'Generatives KI-Modell übersprungen: weniger als 6 GB RAM erkannt ($ramMb MB). Zusammenfassungen, Tags und RAG-Chat sind deaktiviert.';
  }

  @override
  String get downloadSkippedLowDisk =>
      'Generatives KI-Modell übersprungen: nicht genügend freier Speicherplatz (mindestens 2 GB benötigt). Geben Sie Speicher frei und starten Sie die App neu.';

  @override
  String get errorModelNotLoaded =>
      'KI-Modell nicht geladen. Bitte warten Sie auf den Abschluss des Downloads oder versuchen Sie es in den Einstellungen erneut.';

  @override
  String get errorInsufficientRam =>
      'Nicht genügend RAM. Schließen Sie andere Anwendungen und versuchen Sie es erneut.';

  @override
  String get errorInsufficientDisk =>
      'Nicht genügend freier Speicherplatz. Geben Sie mindestens 2 GB frei und versuchen Sie es erneut.';

  @override
  String get errorNetworkUnavailable =>
      'Netzwerkverbindung fehlgeschlagen. Überprüfen Sie Ihre Internetverbindung und versuchen Sie es erneut.';

  @override
  String get settingsAiModelsStatus => 'KI-Modelle';

  @override
  String get settingsEmbeddingModelReady => 'Embedding-Modell: bereit';

  @override
  String get settingsEmbeddingModelMissing =>
      'Embedding-Modell: nicht heruntergeladen';

  @override
  String get settingsGgufModelReady => 'Generatives Modell: bereit';

  @override
  String get settingsGgufModelMissing =>
      'Generatives Modell: nicht heruntergeladen';

  @override
  String get settingsGgufModelSkippedRam =>
      'Generatives Modell: übersprungen (wenig RAM)';

  @override
  String get settingsGgufModelSkippedDisk =>
      'Generatives Modell: übersprungen (wenig Speicherplatz)';

  @override
  String get downloadFailedRetryHint => 'Tippen zum erneuten Herunterladen';
}
