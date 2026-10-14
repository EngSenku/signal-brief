import 'package:flutter_test/flutter_test.dart';
import 'package:signal_brief/article.dart';

void main() {
  group('readable extraction', () {
    test('keeps article paragraphs and drops chrome', () {
      const html = '''
        <html><head><title>T</title><style>.x{}</style></head>
        <body>
          <nav><a href="/">Home</a><a href="/about">About</a></nav>
          <header>Site header</header>
          <article>
            <h1>The real title</h1>
            <p>First paragraph of the actual article, long enough to matter.</p>
            <p>Second paragraph with more useful detail for the reader.</p>
            <ul><li>Point one</li><li>Point two</li></ul>
          </article>
          <aside>Related links</aside>
          <footer>Copyright</footer>
          <script>console.log('tracking')</script>
        </body></html>''';
      final text = ArticleStore().extractFromHtml(html);

      expect(text, contains('First paragraph'));
      expect(text, contains('Second paragraph'));
      expect(text, contains('## The real title'));
      expect(text, contains('• Point one'));
      expect(text, isNot(contains('Home')));
      expect(text, isNot(contains('Site header')));
      expect(text, isNot(contains('Related links')));
      expect(text, isNot(contains('Copyright')));
      expect(text, isNot(contains('console.log')));
    });

    test('falls back to body text when there is no article container', () {
      const html = '<html><body><div><p>'
          'A reasonably long paragraph that lives directly in a generic div '
          'without any of the known article selectors being present at all, '
          'so the extractor has to fall back to the document body text.'
          '</p></div></body></html>';
      final text = ArticleStore().extractFromHtml(html);
      expect(text, contains('reasonably long paragraph'));
    });

    test('removes nav links and markup from the output', () {
      const html = '<article><p>Hello '
          '<a href="https://x">world</a> how are you</p>'
          '<p>Another full sentence that makes this long enough to be kept '
          'by the extractor rather than discarded as boilerplate.</p></article>';
      final text = ArticleStore().extractFromHtml(html);
      expect(text, contains('Hello'));
      expect(text, isNot(contains('<a')));
    });
  });
}
