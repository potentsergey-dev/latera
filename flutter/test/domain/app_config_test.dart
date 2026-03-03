import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/app_config.dart';

void main() {
  group('AppConfig defaults', () {
    test('defaultConfig has expected default values', () {
      const config = AppConfig.defaultConfig;

      expect(config.resourceSaverEnabled, false);
      expect(config.enableOfficeDocs, true);
      expect(config.enableOcr, false);
      expect(config.enableTranscription, false);
      expect(config.enableEmbeddings, false);
      expect(config.enableSemanticSimilarity, false);
      expect(config.enableRag, false);
      expect(config.enableAutoSummary, false);
      expect(config.enableAutoTags, false);
      expect(config.maxConcurrentJobs, 2);
      expect(config.maxFileSizeMbForEnrichment, 50);
      expect(config.maxMediaMinutes, 60);
      expect(config.maxPagesPerPdf, 100);
    });

    test('resourceSaverPreset has correct values', () {
      const preset = AppConfig.resourceSaverPreset;

      expect(preset.resourceSaverEnabled, true);
      expect(preset.enableOfficeDocs, true);
      expect(preset.enableOcr, false);
      expect(preset.enableTranscription, false);
      expect(preset.enableEmbeddings, false);
      expect(preset.enableSemanticSimilarity, false);
      expect(preset.enableRag, false);
      expect(preset.enableAutoSummary, false);
      expect(preset.enableAutoTags, false);
      expect(preset.maxConcurrentJobs, 1);
      expect(preset.maxFileSizeMbForEnrichment, 10);
      expect(preset.maxMediaMinutes, 0);
      expect(preset.maxPagesPerPdf, 30);
    });
  });

  group('AppConfig.copyWith', () {
    test('copies all new fields correctly', () {
      const original = AppConfig.defaultConfig;

      final modified = original.copyWith(
        resourceSaverEnabled: true,
        enableOfficeDocs: false,
        enableOcr: true,
        enableTranscription: true,
        enableEmbeddings: true,
        enableRag: true,
        enableAutoSummary: true,
        enableAutoTags: true,
        maxConcurrentJobs: 4,
        maxFileSizeMbForEnrichment: 100,
        maxMediaMinutes: 120,
        maxPagesPerPdf: 200,
      );

      expect(modified.resourceSaverEnabled, true);
      expect(modified.enableOfficeDocs, false);
      expect(modified.enableOcr, true);
      expect(modified.enableTranscription, true);
      expect(modified.enableEmbeddings, true);
      expect(modified.enableRag, true);
      expect(modified.enableAutoSummary, true);
      expect(modified.enableAutoTags, true);
      expect(modified.maxConcurrentJobs, 4);
      expect(modified.maxFileSizeMbForEnrichment, 100);
      expect(modified.maxMediaMinutes, 120);
      expect(modified.maxPagesPerPdf, 200);

      // Original should be unchanged
      expect(original.resourceSaverEnabled, false);
      expect(original.enableOfficeDocs, true);
    });

    test('preserves existing fields when not specified', () {
      const original = AppConfig(
        watchPath: '/test',
        notificationsEnabled: false,
        resourceSaverEnabled: true,
        enableOcr: true,
      );

      final copy = original.copyWith(enableOcr: false);

      expect(copy.watchPath, '/test');
      expect(copy.notificationsEnabled, false);
      expect(copy.resourceSaverEnabled, true);
      expect(copy.enableOcr, false);
    });
  });

  group('AppConfig.isFeatureEffectivelyEnabled', () {
    test('returns raw flag when resourceSaver is off', () {
      const config = AppConfig(
        resourceSaverEnabled: false,
        enableOfficeDocs: true,
        enableOcr: true,
        enableTranscription: true,
        enableEmbeddings: true,
        enableSemanticSimilarity: true,
        enableRag: true,
        enableAutoSummary: true,
        enableAutoTags: true,
      );

      expect(config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.ocr), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.transcription), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.embeddings), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.rag), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.autoSummary), true);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.autoTags), true);
    });

    test('officeDocs remains enabled when resourceSaver is on', () {
      const config = AppConfig(
        resourceSaverEnabled: true,
        enableOfficeDocs: true,
      );

      expect(config.isFeatureEffectivelyEnabled(ContentFeature.officeDocs), true);
    });

    test('heavy features are disabled when resourceSaver is on', () {
      const config = AppConfig(
        resourceSaverEnabled: true,
        enableOcr: true,
        enableTranscription: true,
        enableEmbeddings: true,
        enableSemanticSimilarity: true,
        enableRag: true,
        enableAutoSummary: true,
        enableAutoTags: true,
      );

      expect(config.isFeatureEffectivelyEnabled(ContentFeature.ocr), false);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.transcription), false);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.embeddings), false);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), false);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.rag), false);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.autoSummary), false);
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.autoTags), false);
    });

    test('returns false when feature is off regardless of resourceSaver', () {
      const config = AppConfig(
        resourceSaverEnabled: false,
        enableOcr: false,
      );

      expect(config.isFeatureEffectivelyEnabled(ContentFeature.ocr), false);
    });

    test('semanticSimilarity requires both enableSemanticSimilarity and enableEmbeddings', () {
      // Both off
      const config1 = AppConfig(
        enableEmbeddings: false,
        enableSemanticSimilarity: false,
      );
      expect(config1.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), false);

      // Only embeddings on
      const config2 = AppConfig(
        enableEmbeddings: true,
        enableSemanticSimilarity: false,
      );
      expect(config2.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), false);

      // Only semanticSimilarity on
      const config3 = AppConfig(
        enableEmbeddings: false,
        enableSemanticSimilarity: true,
      );
      expect(config3.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), false);

      // Both on
      const config4 = AppConfig(
        enableEmbeddings: true,
        enableSemanticSimilarity: true,
      );
      expect(config4.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), true);
    });

    test('semanticSimilarity disabled in resource saver mode', () {
      const config = AppConfig(
        resourceSaverEnabled: true,
        enableEmbeddings: true,
        enableSemanticSimilarity: true,
      );
      expect(config.isFeatureEffectivelyEnabled(ContentFeature.semanticSimilarity), false);
    });
  });

  group('AppConfig.effectiveLimits', () {
    test('returns user limits when resourceSaver is off', () {
      const config = AppConfig(
        resourceSaverEnabled: false,
        maxConcurrentJobs: 4,
        maxFileSizeMbForEnrichment: 100,
        maxMediaMinutes: 120,
        maxPagesPerPdf: 200,
      );

      final limits = config.effectiveLimits;

      expect(limits.maxConcurrentJobs, 4);
      expect(limits.maxFileSizeMb, 100);
      expect(limits.maxMediaMinutes, 120);
      expect(limits.maxPagesPerPdf, 200);
    });

    test('returns reduced limits when resourceSaver is on', () {
      const config = AppConfig(
        resourceSaverEnabled: true,
        maxConcurrentJobs: 4,
        maxFileSizeMbForEnrichment: 100,
        maxMediaMinutes: 120,
        maxPagesPerPdf: 200,
      );

      final limits = config.effectiveLimits;

      expect(limits.maxConcurrentJobs, 1);
      expect(limits.maxFileSizeMb, 10);
      expect(limits.maxMediaMinutes, 0);
      expect(limits.maxPagesPerPdf, 30);
    });
  });

  group('AppConfig equality', () {
    test('configs with same values are equal', () {
      const a = AppConfig(
        resourceSaverEnabled: true,
        enableOcr: true,
        maxConcurrentJobs: 3,
      );
      const b = AppConfig(
        resourceSaverEnabled: true,
        enableOcr: true,
        maxConcurrentJobs: 3,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('configs with different new fields are not equal', () {
      const a = AppConfig(resourceSaverEnabled: true);
      const b = AppConfig(resourceSaverEnabled: false);

      expect(a, isNot(equals(b)));
    });
  });
}
