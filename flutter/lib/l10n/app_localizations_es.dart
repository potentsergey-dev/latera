// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Latera';

  @override
  String get buttonStart => 'Iniciar';

  @override
  String get buttonSave => 'Guardar';

  @override
  String get buttonSearch => 'Buscar';

  @override
  String get buttonRetry => 'Reintentar';

  @override
  String get onboardingTitle => 'Bienvenido a Latera';

  @override
  String get onboardingSubtitle => 'Tu asistente inteligente de documentos';

  @override
  String get settingsTitle => 'Configuración';

  @override
  String get needsAttentionTitle => 'Requiere atención';

  @override
  String get initializationError => 'Error de inicialización';

  @override
  String get onboardingDescription =>
      'Aplicación para rastrear nuevos archivos en una carpeta.\nSelecciona una carpeta para vigilar:';

  @override
  String get onboardingWhatTracksTitle => 'Qué rastrea la aplicación';

  @override
  String get onboardingWhatTracksItem1 =>
      'Solo archivos nuevos en la carpeta seleccionada';

  @override
  String get onboardingWhatTracksItem2 =>
      'Nombres y rutas de archivos para búsqueda';

  @override
  String get onboardingWhatTracksItem3 => 'El contenido se procesa localmente';

  @override
  String get onboardingPrivacyTitle => 'Privacidad';

  @override
  String get onboardingPrivacyItem1 => 'Los datos no salen de tu dispositivo';

  @override
  String get onboardingPrivacyItem2 =>
      'Los archivos y su contenido no se envían a internet';

  @override
  String get onboardingDataStorageTitle => 'Dónde se almacenan los datos';

  @override
  String get onboardingIndexLocation => 'Índice:';

  @override
  String get onboardingSettingsStorage => 'Configuración: almacenamiento local';

  @override
  String get onboardingFolderSectionTitle => 'Carpeta de vigilancia';

  @override
  String get onboardingSelectFolder => 'Seleccionar carpeta...';

  @override
  String get onboardingCustomFolderProBadge => 'PRO';

  @override
  String get onboardingCustomFolderProHint =>
      'Disponible en prueba PRO — cualquier carpeta';

  @override
  String get onboardingCustomFolderLockedHint =>
      'Requiere PRO — actualiza para usar una carpeta personalizada';

  @override
  String get onboardingUseDefault => 'Usar predeterminada';

  @override
  String get onboardingStartButton => 'Comenzar';

  @override
  String get onboardingChangeLater =>
      'Puedes cambiar la carpeta más tarde en configuración';

  @override
  String get onboardingLoading => 'Cargando...';

  @override
  String onboardingLoadError(String error) {
    return 'Error de carga: $error';
  }

  @override
  String onboardingFolderPickError(String error) {
    return 'Error al seleccionar carpeta: $error';
  }

  @override
  String get onboardingDefaultPathUnavailable =>
      'No se pudo cargar la ruta predeterminada. Por favor, selecciona una carpeta manualmente.';

  @override
  String onboardingSaveError(String error) {
    return 'Error al guardar la configuración: $error';
  }

  @override
  String get settingsSectionWatchFolder => 'Carpeta de vigilancia';

  @override
  String get settingsCurrentPath => 'Ruta actual';

  @override
  String get settingsNotConfigured => 'No configurada';

  @override
  String get settingsSelectFolder => 'Seleccionar carpeta';

  @override
  String get settingsSelectFolderHint =>
      'Elige una carpeta para vigilar nuevos archivos';

  @override
  String get settingsOpenInExplorer => 'Abrir en Explorador';

  @override
  String get settingsOpenInExplorerHint =>
      'Abrir carpeta en el administrador de archivos';

  @override
  String get settingsSelectFolderFirst =>
      'Selecciona primero una carpeta de vigilancia';

  @override
  String get settingsSectionNotifications => 'Notificaciones';

  @override
  String get settingsShowNotifications => 'Mostrar notificaciones';

  @override
  String get settingsShowNotificationsHint =>
      'Notificaciones sobre nuevos archivos en la carpeta';

  @override
  String get settingsSectionPerformance => 'Rendimiento';

  @override
  String get settingsResourceSaver => 'Ahorro de recursos';

  @override
  String get settingsResourceSaverOnHint =>
      'Funciones pesadas desactivadas, límites reducidos';

  @override
  String get settingsResourceSaverOffHint =>
      'Desactivar funciones intensivas en recursos para PCs de gama baja';

  @override
  String get settingsSectionContentProcessing => 'Procesamiento de contenido';

  @override
  String get settingsTextExtraction => 'Extracción de texto';

  @override
  String get settingsTextExtractionHint =>
      'Buscar por contenido de PDF, DOCX y otros';

  @override
  String get settingsOcr => 'Reconocimiento de texto (OCR)';

  @override
  String get settingsOcrHint =>
      'Texto de capturas de pantalla, escaneos y fotos';

  @override
  String get settingsSemanticSearch => 'Búsqueda semántica';

  @override
  String get settingsSemanticSearchHint =>
      'Encontrar documentos similares por significado';

  @override
  String get settingsTranscription => 'Transcripción de medios (Whisper)';

  @override
  String get settingsTranscriptionHint =>
      'Buscar por contenido de audio y video';

  @override
  String get settingsRag => 'Pregunta a tu carpeta (RAG)';

  @override
  String get settingsRagHint => 'Chat con respuestas de tus archivos';

  @override
  String get settingsAutoDescriptions => 'Descripciones automáticas';

  @override
  String get settingsAutoDescriptionsHint => 'Resumen automático de documentos';

  @override
  String get settingsAutoTags => 'Etiquetas automáticas';

  @override
  String get settingsAutoTagsHint =>
      'Asignación automática de etiquetas por contenido';

  @override
  String get settingsComingSoon => 'pronto';

  @override
  String get settingsDisabledByResourceSaver =>
      'desactivado por el modo de ahorro de recursos';

  @override
  String get settingsSectionAdvanced => 'Avanzado';

  @override
  String get settingsResetSettings => 'Restablecer configuración';

  @override
  String get settingsResetHint =>
      'Restablecer toda la configuración a los valores predeterminados';

  @override
  String get settingsResetConfirmTitle => '¿Restablecer configuración?';

  @override
  String get settingsResetConfirmBody =>
      'Toda la configuración se restablecerá a los valores predeterminados. La carpeta de vigilancia se restablecerá.';

  @override
  String get settingsResetDone => 'Configuración restablecida';

  @override
  String get settingsVersion => 'Versión';

  @override
  String settingsFolderChanged(String path) {
    return 'Carpeta cambiada: $path';
  }

  @override
  String get settingsChangeFolderConfirmTitle =>
      '¿Cambiar carpeta de vigilancia?';

  @override
  String settingsChangeFolderConfirmBody(String path) {
    return 'Los archivos indexados previamente de la carpeta actual se eliminarán del índice de búsqueda. No se eliminarán del disco.\n\nNueva carpeta: $path';
  }

  @override
  String get settingsChangeFolderConfirmButton => 'Cambiar carpeta';

  @override
  String settingsFolderPickError(String error) {
    return 'Error al seleccionar carpeta: $error';
  }

  @override
  String get settingsFolderNotSelected => 'Carpeta no seleccionada';

  @override
  String settingsFolderNotExists(String path) {
    return 'La carpeta no existe: $path';
  }

  @override
  String get settingsPathDangerousChars =>
      'La ruta contiene caracteres inválidos';

  @override
  String settingsOpenFolderError(String error) {
    return 'Error al abrir la carpeta: $error';
  }

  @override
  String get settingsLoadError => 'Error al cargar la configuración';

  @override
  String get buttonCancel => 'Cancelar';

  @override
  String get buttonReset => 'Restablecer';

  @override
  String get trayShowWindow => 'Abrir Latera';

  @override
  String get trayQuit => 'Salir';

  @override
  String get notificationFileNeedsReviewTitle =>
      'Archivo añadido sin reconocimiento';

  @override
  String notificationFileNeedsReviewBody(String fileName) {
    return 'Archivo $fileName añadido sin reconocimiento. Por favor, añade una descripción manualmente.';
  }

  @override
  String get settingsSectionLicense => 'Licencia';

  @override
  String get settingsSectionLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Política de privacidad';

  @override
  String get settingsTermsOfUse => 'Términos de uso';

  @override
  String get licenseCurrentMode => 'Modo actual: ';

  @override
  String get licenseDescriptionPro =>
      'Licencia PRO activa. Todas las funciones disponibles sin restricciones.';

  @override
  String licenseDescriptionTrial(int days) {
    return 'Período de prueba PRO ($days días restantes). Todas las funciones disponibles. Después del período de prueba, la app cambiará al modo Básico con límites de archivos y funciones restringidas.';
  }

  @override
  String get licenseDescriptionBasic =>
      'Versión gratuita con restricciones: límite de archivos indexados, funciones intensivas en recursos desactivadas (búsqueda semántica, descripciones automáticas, transcripción).';

  @override
  String get licenseHardwareConstraintsTitle => 'Restricciones de hardware';

  @override
  String get licenseHardwareConstraintsBody =>
      'Se detectó menos de 6 GB de RAM. Las funciones PRO no están disponibles independientemente del estado de la licencia.';

  @override
  String get licenseBuyPro => 'Comprar PRO — compra única';

  @override
  String get licensePurchasing => 'Procesando...';

  @override
  String get licenseRestorePurchases => 'Restaurar compra';

  @override
  String get licenseRestoring => 'Verificando...';

  @override
  String get licenseActivatedTitle => '¡PRO activado!';

  @override
  String get licenseActivatedBody =>
      'Gracias por tu compra. Todas las funciones PRO están ahora disponibles.';

  @override
  String get licenseRestoredTitle => '¡Compra restaurada!';

  @override
  String get licenseRestoredBody =>
      'Versión PRO restaurada con éxito. Todas las funciones están disponibles.';

  @override
  String get licenseRestoreNotFound =>
      'Compra PRO no encontrada en Microsoft Store.';

  @override
  String licenseRestoreError(String error) {
    return 'Error al restaurar la compra: $error';
  }

  @override
  String get licenseStoreUnavailable =>
      'Microsoft Store no disponible. Asegúrate de que la app fue instalada desde la Store.';

  @override
  String licensePurchaseError(String error) {
    return 'Error de compra: $error';
  }

  @override
  String get trialExpiredCustomFolderBannerTitle => 'Prueba PRO expirada';

  @override
  String get trialExpiredCustomFolderBannerBody =>
      'La carpeta de vigilancia personalizada es una función PRO. Tus datos indexados se conservan. Cambia a la carpeta predeterminada o actualiza a PRO para continuar.';

  @override
  String get trialExpiredSwitchToDefault => 'Usar carpeta predeterminada';

  @override
  String get trialExpiredUpgradePro => 'Actualizar a PRO';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsLanguage => 'Idioma de la interfaz';

  @override
  String get settingsLanguageHint =>
      'Elige el idioma de visualización de la aplicación';

  @override
  String get settingsLanguageSystem => 'Predeterminado del sistema';

  @override
  String get settingsLanguageRestartHint =>
      'Reinicia la aplicación para aplicar el nuevo idioma';
}
