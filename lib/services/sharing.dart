import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Receives links/text shared from other apps into Signal's reading list.
///
/// Implemented with a tiny platform channel handled by `MainActivity.kt`
/// (the `ACTION_SEND` intent filter lives in the Android manifest). Keeping
/// this in-house avoids a plugin that kept raising our Android compileSdk.
class Sharing {
  static const MethodChannel _channel = MethodChannel('signal/share');

  void Function(List<String>)? _onShared;

  /// Only Android is wired up natively; iOS would need a Share Extension
  /// target added in Xcode (see the README).
  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> init(void Function(List<String> texts) onShared) async {
    if (!supported) return;
    _onShared = onShared;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shared' && call.arguments is String) {
        final v = (call.arguments as String).trim();
        if (v.isNotEmpty) _onShared?.call([v]);
      }
      return null;
    });
    try {
      final initial = await _channel.invokeMethod<String>('getInitial');
      final v = initial?.trim();
      if (v != null && v.isNotEmpty) _onShared?.call([v]);
    } catch (e) {
      debugPrint('share init failed: $e');
    }
  }

  void dispose() {
    _channel.setMethodCallHandler(null);
    _onShared = null;
  }
}
