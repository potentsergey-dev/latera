// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Latera';

  @override
  String get buttonStart => 'Iniciar';

  @override
  String get buttonSave => 'Salvar';

  @override
  String get buttonSearch => 'Buscar';

  @override
  String get buttonRetry => 'Tentar novamente';

  @override
  String get onboardingTitle => 'Bem-vindo ao Latera';

  @override
  String get onboardingSubtitle => 'Seu assistente inteligente de documentos';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get needsAttentionTitle => 'Requer atenção';

  @override
  String get initializationError => 'Erro de inicialização';

  @override
  String get onboardingDescription =>
      'Aplicativo para rastrear novos arquivos em uma pasta.\nSelecione uma pasta para monitorar:';

  @override
  String get onboardingWhatTracksTitle => 'O que o aplicativo rastreia';

  @override
  String get onboardingWhatTracksItem1 =>
      'Apenas novos arquivos na pasta selecionada';

  @override
  String get onboardingWhatTracksItem2 =>
      'Nomes e caminhos de arquivos para busca';

  @override
  String get onboardingWhatTracksItem3 => 'O conteúdo é processado localmente';

  @override
  String get onboardingPrivacyTitle => 'Privacidade';

  @override
  String get onboardingPrivacyItem1 => 'Os dados não saem do seu dispositivo';

  @override
  String get onboardingPrivacyItem2 =>
      'Arquivos e seu conteúdo não são enviados para a internet';

  @override
  String get onboardingDataStorageTitle => 'Onde os dados são armazenados';

  @override
  String get onboardingIndexLocation => 'Índice:';

  @override
  String get onboardingSettingsStorage => 'Configurações: armazenamento local';

  @override
  String get onboardingFolderSectionTitle => 'Pasta de monitoramento';

  @override
  String get onboardingSelectFolder => 'Selecionar pasta...';

  @override
  String get onboardingCustomFolderProBadge => 'PRO';

  @override
  String get onboardingCustomFolderProHint =>
      'Disponível na versão de teste PRO — qualquer pasta';

  @override
  String get onboardingCustomFolderLockedHint =>
      'Requer PRO — atualize para usar uma pasta personalizada';

  @override
  String get onboardingUseDefault => 'Usar padrão';

  @override
  String get onboardingStartButton => 'Começar';

  @override
  String get onboardingChangeLater =>
      'Você pode alterar a pasta depois nas configurações';

  @override
  String get onboardingLoading => 'Carregando...';

  @override
  String onboardingLoadError(String error) {
    return 'Erro ao carregar: $error';
  }

  @override
  String onboardingFolderPickError(String error) {
    return 'Erro ao selecionar pasta: $error';
  }

  @override
  String get onboardingDefaultPathUnavailable =>
      'Não foi possível carregar o caminho padrão. Por favor, selecione uma pasta manualmente.';

  @override
  String onboardingSaveError(String error) {
    return 'Erro ao salvar configurações: $error';
  }

  @override
  String get settingsSectionWatchFolder => 'Pasta de monitoramento';

  @override
  String get settingsCurrentPath => 'Caminho atual';

  @override
  String get settingsNotConfigured => 'Não configurada';

  @override
  String get settingsSelectFolder => 'Selecionar pasta';

  @override
  String get settingsSelectFolderHint =>
      'Escolha uma pasta para monitorar novos arquivos';

  @override
  String get settingsOpenInExplorer => 'Abrir no Explorador';

  @override
  String get settingsOpenInExplorerHint =>
      'Abrir pasta no gerenciador de arquivos';

  @override
  String get settingsSelectFolderFirst =>
      'Selecione primeiro uma pasta de monitoramento';

  @override
  String get settingsSectionNotifications => 'Notificações';

  @override
  String get settingsShowNotifications => 'Mostrar notificações';

  @override
  String get settingsShowNotificationsHint =>
      'Notificações sobre novos arquivos na pasta';

  @override
  String get settingsSectionPerformance => 'Desempenho';

  @override
  String get settingsResourceSaver => 'Economia de recursos';

  @override
  String get settingsResourceSaverOnHint =>
      'Recursos pesados desativados, limites reduzidos';

  @override
  String get settingsResourceSaverOffHint =>
      'Desativar recursos intensivos para PCs de baixo desempenho';

  @override
  String get settingsSectionContentProcessing => 'Processamento de conteúdo';

  @override
  String get settingsTextExtraction => 'Extração de texto';

  @override
  String get settingsTextExtractionHint =>
      'Buscar por conteúdo de PDF, DOCX e outros';

  @override
  String get settingsOcr => 'Reconhecimento de texto (OCR)';

  @override
  String get settingsOcrHint =>
      'Texto de capturas de tela, digitalizações e fotos';

  @override
  String get settingsSemanticSearch => 'Busca semântica';

  @override
  String get settingsSemanticSearchHint =>
      'Encontrar documentos similares por significado';

  @override
  String get settingsTranscription => 'Transcrição de mídia (Whisper)';

  @override
  String get settingsTranscriptionHint =>
      'Buscar por conteúdo de áudio e vídeo';

  @override
  String get settingsRag => 'Pergunte à sua pasta (RAG)';

  @override
  String get settingsRagHint => 'Chat com respostas dos seus arquivos';

  @override
  String get settingsAutoDescriptions => 'Descrições automáticas';

  @override
  String get settingsAutoDescriptionsHint => 'Resumo automático de documentos';

  @override
  String get settingsAutoTags => 'Tags automáticas';

  @override
  String get settingsAutoTagsHint =>
      'Atribuição automática de tags por conteúdo';

  @override
  String get settingsComingSoon => 'em breve';

  @override
  String get settingsDisabledByResourceSaver =>
      'desativado pelo modo de economia de recursos';

  @override
  String get settingsSectionAdvanced => 'Avançado';

  @override
  String get settingsResetSettings => 'Redefinir configurações';

  @override
  String get settingsResetHint => 'Retornar todas as configurações aos padrões';

  @override
  String get settingsResetConfirmTitle => 'Redefinir configurações?';

  @override
  String get settingsResetConfirmBody =>
      'Todas as configurações serão retornadas aos padrões. A pasta de monitoramento será redefinida.';

  @override
  String get settingsResetDone => 'Configurações redefinidas';

  @override
  String get settingsVersion => 'Versão';

  @override
  String settingsFolderChanged(String path) {
    return 'Pasta alterada: $path';
  }

  @override
  String get settingsChangeFolderConfirmTitle =>
      'Alterar pasta de monitoramento?';

  @override
  String settingsChangeFolderConfirmBody(String path) {
    return 'Arquivos indexados anteriormente da pasta atual serão removidos do índice de busca. Eles não serão excluídos do disco.\n\nNova pasta: $path';
  }

  @override
  String get settingsChangeFolderConfirmButton => 'Alterar pasta';

  @override
  String settingsFolderPickError(String error) {
    return 'Erro ao selecionar pasta: $error';
  }

  @override
  String get settingsFolderNotSelected => 'Pasta não selecionada';

  @override
  String settingsFolderNotExists(String path) {
    return 'A pasta não existe: $path';
  }

  @override
  String get settingsPathDangerousChars =>
      'O caminho contém caracteres inválidos';

  @override
  String settingsOpenFolderError(String error) {
    return 'Erro ao abrir a pasta: $error';
  }

  @override
  String get settingsLoadError => 'Erro ao carregar configurações';

  @override
  String get buttonCancel => 'Cancelar';

  @override
  String get buttonReset => 'Redefinir';

  @override
  String get trayShowWindow => 'Abrir Latera';

  @override
  String get trayQuit => 'Sair';

  @override
  String get notificationFileNeedsReviewTitle =>
      'Arquivo adicionado sem reconhecimento';

  @override
  String notificationFileNeedsReviewBody(String fileName) {
    return 'Arquivo $fileName adicionado sem reconhecimento. Por favor, adicione uma descrição manualmente.';
  }

  @override
  String get settingsSectionLicense => 'Licença';

  @override
  String get settingsSectionLegal => 'Legal';

  @override
  String get settingsPrivacyPolicy => 'Política de Privacidade';

  @override
  String get settingsTermsOfUse => 'Termos de Uso';

  @override
  String get licenseCurrentMode => 'Modo atual: ';

  @override
  String get licenseDescriptionPro =>
      'Licença PRO ativa. Todos os recursos disponíveis sem restrições.';

  @override
  String licenseDescriptionTrial(int days) {
    return 'Período de teste PRO ($days dias restantes). Todos os recursos disponíveis. Após o término do teste, o app mudará para o modo Básico com limites de arquivos e recursos restritos.';
  }

  @override
  String get licenseDescriptionBasic =>
      'Versão gratuita com restrições: limite de arquivos indexados, recursos intensivos desativados (busca semântica, descrições automáticas, transcrição).';

  @override
  String get licenseHardwareConstraintsTitle => 'Restrições de hardware';

  @override
  String get licenseHardwareConstraintsBody =>
      'Menos de 6 GB de RAM detectados. Os recursos PRO não estão disponíveis independentemente do status da licença.';

  @override
  String get licenseBuyPro => 'Comprar PRO — compra única';

  @override
  String get licensePurchasing => 'Processando...';

  @override
  String get licenseRestorePurchases => 'Restaurar compra';

  @override
  String get licenseRestoring => 'Verificando...';

  @override
  String get licenseActivatedTitle => 'PRO ativado!';

  @override
  String get licenseActivatedBody =>
      'Obrigado pela sua compra. Todos os recursos PRO estão agora disponíveis.';

  @override
  String get licenseRestoredTitle => 'Compra restaurada!';

  @override
  String get licenseRestoredBody =>
      'Versão PRO restaurada com sucesso. Todos os recursos estão disponíveis.';

  @override
  String get licenseRestoreNotFound =>
      'Compra PRO não encontrada na Microsoft Store.';

  @override
  String licenseRestoreError(String error) {
    return 'Erro ao restaurar a compra: $error';
  }

  @override
  String get licenseStoreUnavailable =>
      'Microsoft Store não disponível. Certifique-se de que o app foi instalado pela Store.';

  @override
  String licensePurchaseError(String error) {
    return 'Erro de compra: $error';
  }

  @override
  String get trialExpiredCustomFolderBannerTitle => 'Teste PRO expirado';

  @override
  String get trialExpiredCustomFolderBannerBody =>
      'A pasta de monitoramento personalizada é um recurso PRO. Seus dados indexados são preservados. Mude para a pasta padrão ou atualize para PRO para continuar.';

  @override
  String get trialExpiredSwitchToDefault => 'Usar pasta padrão';

  @override
  String get trialExpiredUpgradePro => 'Atualizar para PRO';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsLanguage => 'Idioma da interface';

  @override
  String get settingsLanguageHint =>
      'Escolha o idioma de exibição do aplicativo';

  @override
  String get settingsLanguageSystem => 'Padrão do sistema';

  @override
  String get settingsLanguageRestartHint =>
      'Reinicie o aplicativo para aplicar o novo idioma';

  @override
  String get onboardingAiModelsTitle => 'Modelos de IA';

  @override
  String get onboardingAiModelsItem1 =>
      'Modelos de IA (~1,8 GB) são baixados na primeira execução';

  @override
  String get onboardingAiModelsItem2 =>
      'Os modelos são usados para busca semântica e resumos de documentos';

  @override
  String get onboardingAiModelsItem3 =>
      'Fonte de download: Hugging Face (repositório público)';

  @override
  String get onboardingModelsLocation => 'Modelos:';

  @override
  String get onboardingPrivacyItem3 =>
      'Modelos de IA são baixados uma vez — sem transferência contínua de dados';

  @override
  String get downloadFailedTitle => 'Falha no download';

  @override
  String get downloadFailedEmbedding =>
      'Não foi possível baixar o modelo de embeddings. A busca semântica não funcionará até que o modelo seja baixado.';

  @override
  String get downloadFailedGguf =>
      'Não foi possível baixar o modelo generativo. Resumos, tags e chat RAG não funcionarão até que o modelo seja baixado.';

  @override
  String get downloadRetryButton => 'Tentar download novamente';

  @override
  String downloadSkippedLowRam(int ramMb) {
    return 'Modelo de IA generativa ignorado: menos de 6 GB de RAM detectados ($ramMb MB). Resumos, tags e chat RAG estão desativados.';
  }

  @override
  String get downloadSkippedLowDisk =>
      'Modelo de IA generativa ignorado: espaço em disco insuficiente (necessário pelo menos 2 GB). Libere espaço e reinicie o aplicativo.';

  @override
  String get errorModelNotLoaded =>
      'Modelo de IA não carregado. Aguarde o término do download ou tente novamente nas Configurações.';

  @override
  String get errorInsufficientRam =>
      'RAM insuficiente. Feche outros aplicativos e tente novamente.';

  @override
  String get errorInsufficientDisk =>
      'Espaço em disco insuficiente. Libere pelo menos 2 GB e tente novamente.';

  @override
  String get errorNetworkUnavailable =>
      'Falha na conexão de rede. Verifique sua conexão com a internet e tente novamente.';

  @override
  String get settingsAiModelsStatus => 'Modelos de IA';

  @override
  String get settingsEmbeddingModelReady => 'Modelo de embeddings: pronto';

  @override
  String get settingsEmbeddingModelMissing =>
      'Modelo de embeddings: não baixado';

  @override
  String get settingsGgufModelReady => 'Modelo generativo: pronto';

  @override
  String get settingsGgufModelMissing => 'Modelo generativo: não baixado';

  @override
  String get settingsGgufModelSkippedRam =>
      'Modelo generativo: ignorado (pouca RAM)';

  @override
  String get settingsGgufModelSkippedDisk =>
      'Modelo generativo: ignorado (pouco espaço em disco)';

  @override
  String get downloadFailedRetryHint =>
      'Toque para tentar o download novamente';

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
