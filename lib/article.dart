import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'feeds.dart';

/// A minimal readability pass: fetch a page, keep its readable blocks, and
/// cache the plain text on disk so it can be read without a connection.
class ArticleStore {
  Directory? _dir;

  Future<Directory> _ensureDir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/offline');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  String _name(String url) => sha1.convert(utf8.encode(url)).toString();

  Future<File> _file(String url) async =>
      File('${(await _ensureDir()).path}/${_name(url)}.txt');

  Future<bool> exists(String url) async {
    try {
      return await (await _file(url)).exists();
    } catch (_) {
      return false;
    }
  }

  Future<String?> read(String url) async {
    try {
      final f = await _file(url);
      if (!await f.exists()) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String url) async {
    try {
      final f = await _file(url);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// Download [url], extract readable text, persist it, and return the text.
  Future<String> fetchAndSave(String url) async {
    final text = await extractReadable(url);
    if (text.trim().isEmpty) {
      throw Exception('Could not find readable text on that page.');
    }
    await (await _file(url)).writeAsString(text);
    return text;
  }

  /// Fetch [url] and return plain readable text.
  Future<String> extractReadable(String url) async {
    final r = await http
        .get(Uri.parse(url),
            headers: {'User-Agent': kUserAgent, 'Accept': 'text/html,*/*'})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) {
      throw Exception('Could not download the article (${r.statusCode}).');
    }
    return extractFromHtml(utf8.decode(r.bodyBytes, allowMalformed: true));
  }

  @visibleForTesting
  String extractFromHtml(String rawHtml) {
    final doc = html_parser.parse(rawHtml);
    for (final sel in [
      'script', 'style', 'noscript', 'nav', 'header', 'footer', 'aside',
      'form', 'iframe', 'svg', 'button', 'figure', '.advert', '.ads',
      '[role=navigation]', '[aria-hidden=true]',
    ]) {
      for (final e in doc.querySelectorAll(sel)) {
        e.remove();
      }
    }

    dom.Element? best;
    var bestLen = 0;
    for (final sel in [
      'article', 'main', '[role=main]', '.post-content', '.entry-content',
      '.article-body', '.content', '#content',
    ]) {
      for (final e in doc.querySelectorAll(sel)) {
        final len = e.text.trim().length;
        if (len > bestLen) {
          bestLen = len;
          best = e;
        }
      }
    }
    final root = best ?? doc.body;
    if (root == null) return '';

    final blocks = <String>[];
    for (final el in root.querySelectorAll('h1,h2,h3,h4,p,li,blockquote,pre')) {
      var t = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.length < 2) continue;
      // Skip obvious boilerplate / nav remnants.
      if (RegExp(r'^(cookie|subscribe|sign in|share|advertisement|advert)',
              caseSensitive: false)
          .hasMatch(t)) {
        continue;
      }
      final tag = el.localName;
      if (tag == 'h1' || tag == 'h2' || tag == 'h3' || tag == 'h4') {
        blocks.add('\n## $t');
      } else if (tag == 'li') {
        blocks.add('• $t');
      } else {
        blocks.add(t);
      }
    }

    var text = blocks.join('\n\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (text.isEmpty) {
      final sb = StringBuffer();
      _collect(root, sb);
      text = sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    if (text.length > 200000) text = text.substring(0, 200000);
    return text;
  }

  /// Depth-first text collector that keeps words separated.
  void _collect(dom.Node node, StringBuffer sb) {
    if (node is dom.Text) {
      sb.write(node.text);
      sb.write(' ');
    } else {
      for (final child in node.nodes) {
        _collect(child, sb);
      }
    }
  }
}
