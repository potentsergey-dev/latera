import 'package:flutter_test/flutter_test.dart';
import 'package:latera/domain/rag.dart';
import 'package:latera/infrastructure/rust/stub_rag_service.dart';

void main() {
  group('RagQueryResult', () {
    test('isSuccess returns true when errorCode is null', () {
      const result = RagQueryResult(
        answer: 'Some answer',
        sources: [],
      );
      expect(result.isSuccess, isTrue);
      expect(result.hasAnswer, isTrue);
    });

    test('isSuccess returns false when errorCode is set', () {
      const result = RagQueryResult(
        answer: '',
        sources: [],
        errorCode: 'empty_question',
      );
      expect(result.isSuccess, isFalse);
      expect(result.hasAnswer, isFalse);
    });

    test('sourceCount returns correct number of sources', () {
      const result = RagQueryResult(
        answer: 'Answer',
        sources: [
          RagSource(
            filePath: '/docs/a.txt',
            chunkSnippet: 'snippet 1',
            chunkOffset: 0,
          ),
          RagSource(
            filePath: '/docs/b.txt',
            chunkSnippet: 'snippet 2',
            chunkOffset: 100,
          ),
        ],
      );
      expect(result.sourceCount, 2);
    });

    test('toString includes all relevant info', () {
      const result = RagQueryResult(
        answer: 'Test answer',
        sources: [
          RagSource(
            filePath: '/docs/a.txt',
            chunkSnippet: 'snippet',
            chunkOffset: 0,
          ),
        ],
      );
      final str = result.toString();
      expect(str, contains('success: true'));
      expect(str, contains('sources: 1'));
    });
  });

  group('RagSource', () {
    test('toString includes file path and offset', () {
      const source = RagSource(
        filePath: '/docs/test.txt',
        chunkSnippet: 'Hello world',
        chunkOffset: 42,
      );
      final str = source.toString();
      expect(str, contains('/docs/test.txt'));
      expect(str, contains('42'));
    });
  });

  group('StubRagService', () {
    late StubRagService service;

    setUp(() {
      service = StubRagService();
    });

    test('returns empty_question for empty input', () async {
      final result = await service.query('');
      expect(result.errorCode, 'empty_question');
      expect(result.hasAnswer, isFalse);
      expect(result.sources, isEmpty);
    });

    test('returns empty_question for whitespace input', () async {
      final result = await service.query('   ');
      expect(result.errorCode, 'empty_question');
      expect(result.hasAnswer, isFalse);
    });

    test('returns not_implemented for valid question', () async {
      final result = await service.query('What is Rust?');
      expect(result.errorCode, 'not_implemented');
      expect(result.hasAnswer, isFalse);
      expect(result.sources, isEmpty);
    });

    test('respects topK parameter without error', () async {
      final result = await service.query('test', topK: 3);
      expect(result.errorCode, 'not_implemented');
    });
  });
}
