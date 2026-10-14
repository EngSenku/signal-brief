import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// Models offered in Settings (all served by NVIDIA NIM). Verified to respond
/// with the built-in key; the list is trimmed to chat models that work today.
const kAiModels = <String, String>{
  'nvidia/nemotron-3.5-lightning-30b-a3b':
      'Nemotron 3.5 Lightning 30B — default, fast',
  'nvidia/nemotron-3-nano-omni-30b-a3b-reasoning':
      'Nemotron 3 Nano Omni 30B — reasoning',
  'nvidia/nemotron-3-super-120b-a12b': 'Nemotron 3 Super 120B — strongest reasoning',
  'meta/muse-glimmer-30b': 'Muse Glimmer 30B',
  'openai/gpt-oss-20b': 'GPT-OSS 20B — fast, strong',
  'z-ai/glm-5.3-flash': 'GLM 5.3 Flash',
  'deepseek-ai/deepseek-v4.1-flash': 'DeepSeek V4.1 Flash',
};

const kDefaultModel = 'nvidia/nemotron-3.5-lightning-30b-a3b';

/// Built-in NVIDIA API key, so the app works out of the box for a local build.
///
/// There is no key in source control. Resolution order:
///   1. `--dart-define=NVIDIA_API_KEY=...` (or `--dart-define-from-file=.env`)
///   2. `.env` at the project root (gitignored), loaded at startup
///   3. empty — the user then adds their key in Settings
///
/// The user can always override it in Settings; their key is kept in the OS
/// keychain. Note: any key bundled into an app can be extracted from the APK.
String get kEmbeddedApiKey {
  const fromDefine = String.fromEnvironment('NVIDIA_API_KEY');
  if (fromDefine.isNotEmpty) return fromDefine;
  if (dotenv.isInitialized) {
    final v = dotenv.env['NVIDIA_API_KEY'];
    if (v != null && v.isNotEmpty) return v;
  }
  return '';
}

/// A friendly, user-displayable AI failure.
class AiException implements Exception {
  final String message;
  final bool retryable;
  const AiException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

/// Internal marker: the model returned no visible content (usually because it
/// spent the whole budget reasoning). Triggering a retry keeps chain-of-thought
/// out of the UI.
class _EmptyReply implements Exception {
  const _EmptyReply();
}

/// One way of calling the model, with its own token multiplier.
class _Attempt {
  final bool thinking;
  final int multiplier;
  const _Attempt(this.thinking, this.multiplier);
}

/// Tiny client for the NVIDIA NIM chat-completions endpoint.
class NvidiaClient {
  NvidiaClient({required this.apiKey, required this.model});

  final String apiKey;
  final String model;

  static final Uri _endpoint =
      Uri.parse('https://integrate.api.nvidia.com/v1/chat/completions');

  /// Models such as Nemotron "reasoning" variants spend most of the token
  /// budget on hidden chain-of-thought before writing the answer, so requests
  /// to them get extra headroom and (where supported) an explicit request to
  /// answer directly instead.
  static bool isReasoningModel(String m) {
    final s = m.toLowerCase();
    return s.contains('nemotron') ||
        s.contains('deepseek') ||
        s.contains('glm') ||
        s.contains('gpt-oss') ||
        s.contains('muse') ||
        s.contains('glimmer') ||
        s.contains('reasoning') ||
        s.contains('qwen');
  }

  /// Ask the model to answer immediately, without hidden reasoning, so
  /// summaries stay short and never leak chain-of-thought ("the prompt says…").
  /// Most NVIDIA NIM models accept this flag; if a model rejects it, or the
  /// answer comes back empty, [complete] retries with reasoning allowed and a
  /// larger budget.
  Future<String> complete(
    List<Map<String, String>> messages, {
    int maxTokens = 1200,
    double temperature = 0.3,
    bool thinking = false,
  }) async {
    if (apiKey.isEmpty) {
      throw const AiException('Add your NVIDIA API key in Settings first.');
    }

    final tries = <_Attempt>[
      _Attempt(thinking, thinking ? 4 : 1),
      if (!thinking) const _Attempt(true, 4),
    ];

    AiException? lastError;
    for (final t in tries) {
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          return await _send(messages, maxTokens * t.multiplier, temperature, t.thinking);
        } on _EmptyReply {
          break; // Nothing usable from this variant; try the next one.
        } on AiException catch (e) {
          lastError = e;
          if (!e.retryable || attempt == 3) break;
          await Future.delayed(Duration(milliseconds: 900 * attempt * attempt));
        } on TimeoutException {
          lastError = const AiException(
              'The AI request timed out. Check your connection and try again.',
              retryable: true);
          if (attempt == 3) break;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        } catch (e) {
          lastError = AiException('Could not reach NVIDIA: $e');
          if (attempt == 3) break;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    }
    throw lastError ??
        const AiException('The AI request failed. Try again.', retryable: true);
  }

  Future<String> _send(
    List<Map<String, String>> messages,
    int budget,
    double temperature,
    bool thinking,
  ) async {
    final body = <String, dynamic>{
      'model': model,
      'temperature': temperature,
      'max_tokens': budget,
      'messages': messages,
    };
    if (!thinking) {
      body['chat_template_kwargs'] = {'enable_thinking': false};
    }

    final r = await http
        .post(
          _endpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120));

    if (r.statusCode != 200) {
      // A model may reject the thinking flag outright; retry once without it.
      if (!thinking && (r.statusCode == 400 || r.statusCode == 422)) {
        return _send(messages, budget, temperature, true);
      }
      throw _mapError(r.statusCode, r.bodyBytes);
    }

    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final content = j['choices']?[0]?['message']?['content']?.toString().trim() ?? '';
    if (content.isEmpty) throw const _EmptyReply();
    return content;
  }

  AiException _mapError(int status, List<int> bodyBytes) {
    String detail = '';
    try {
      final j = jsonDecode(utf8.decode(bodyBytes));
      detail = (j['detail'] ?? j['error']?['message'] ?? '').toString();
    } catch (_) {}
    switch (status) {
      case 401:
        return const AiException(
            'Your NVIDIA API key was rejected (401). Re-check it in Settings.');
      case 403:
        return const AiException(
            'This key cannot use that model (403). Pick another model in Settings.');
      case 402:
        return const AiException(
            'NVIDIA reports no credit for this key (402).');
      case 404:
        return AiException(
            'Model not found (404). Try a different model in Settings.'
            '${detail.isEmpty ? '' : ' — $detail'}');
      case 422:
        return AiException('The request was rejected (422). ${detail.isEmpty ? '' : detail}');
      case 429:
        return const AiException(
            'Rate limit reached (429). Wait a moment and try again.',
            retryable: true);
      default:
        return AiException(
            'NVIDIA returned $status.${detail.isEmpty ? '' : ' $detail'}',
            retryable: status >= 500);
    }
  }
}

/// Strip ```json fences and pull the first JSON array/object out of a reply.
String extractJson(String raw) {
  var s = raw.trim();
  final fence = RegExp(r'```(?:json)?', caseSensitive: false);
  s = s.replaceAll(fence, '').replaceAll('```', '').trim();
  final start = s.indexOf(RegExp(r'[\[{]'));
  if (start < 0) return s;
  final open = s[start];
  final close = open == '[' ? ']' : '}';
  var depth = 0;
  for (var i = start; i < s.length; i++) {
    if (s[i] == open) depth++;
    if (s[i] == close) {
      depth--;
      if (depth == 0) return s.substring(start, i + 1);
    }
  }
  return s.substring(start);
}
