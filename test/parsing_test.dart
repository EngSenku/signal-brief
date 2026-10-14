import 'package:flutter_test/flutter_test.dart';
import 'package:signal_brief/ai.dart';
import 'package:signal_brief/feeds.dart';

void main() {
  group('extractJson', () {
    test('pulls a JSON array out of fenced prose', () {
      const raw = 'Sure! Here you go:\n```json\n'
          '[{"front":"Q1","back":"A1"},{"front":"Q2","back":"A2"}]\n```\nEnjoy!';
      final out = extractJson(raw);
      expect(out, '[{"front":"Q1","back":"A1"},{"front":"Q2","back":"A2"}]');
    });

    test('handles an object with nested braces', () {
      final out = extractJson('prefix {"a": {"b": 1}} suffix');
      expect(out, '{"a": {"b": 1}}');
    });

    test('returns the input when there is no json', () {
      expect(extractJson('plain text'), 'plain text');
    });
  });

  group('isReasoningModel', () {
    test('flags Nemotron, DeepSeek R1 and friends', () {
      expect(NvidiaClient.isReasoningModel('nvidia/nemotron-3.5-lightning-30b-a3b'),
          isTrue);
      expect(NvidiaClient.isReasoningModel('deepseek-ai/deepseek-r1'), isTrue);
      expect(NvidiaClient.isReasoningModel('qwen/qwen3-32b'), isTrue);
    });

    test('leaves plain instruct models alone', () {
      expect(NvidiaClient.isReasoningModel('meta/llama-3.3-70b-instruct'), isFalse);
      expect(NvidiaClient.isReasoningModel('meta/llama-3.1-8b-instruct'), isFalse);
    });
  });

  group('cleanText', () {
    test('strips tags and decodes entities', () {
      expect(cleanText('<p>Hello &amp; welcome</p>'), 'Hello & welcome');
    });

    test('drops arXiv boilerplate and reddit bylines', () {
      expect(cleanText('Comments URL blah'), '');
      expect(cleanText('Great paper. Submitted by user12.'), 'Great paper.');
    });

    test('collapses whitespace and handles null', () {
      expect(cleanText('a   \n  b'), 'a b');
      expect(cleanText(null), '');
    });
  });

  group('parseDate', () {
    test('parses ISO 8601', () {
      expect(parseDate('2026-01-02T03:04:05Z')?.toUtc().hour, 3);
    });

    test('parses RFC 822', () {
      final d = parseDate('Mon, 02 Jan 2006 15:04:05 +0000');
      expect(d?.toUtc().year, 2006);
      expect(d?.toUtc().hour, 15);
    });

    test('parses the space-separated feed format', () {
      final d = parseDate('02 Jan 2006 15:04:05 +0100');
      expect(d?.toUtc().hour, 14);
    });

    test('returns null for junk', () {
      expect(parseDate('not a date'), isNull);
      expect(parseDate(null), isNull);
    });
  });
}
