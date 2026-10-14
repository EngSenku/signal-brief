import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signal_brief/screens/brief.dart';
import 'package:signal_brief/screens/report.dart';
import 'package:signal_brief/screens/saved.dart';
import 'package:signal_brief/screens/settings.dart';
import 'package:signal_brief/screens/study.dart';
import 'package:signal_brief/screens/trends.dart';
import 'package:signal_brief/store.dart';
import 'package:signal_brief/study.dart';
import 'package:signal_brief/theme.dart';

Widget _wrap(AppState s, Widget child) => ChangeNotifierProvider.value(
      value: s,
      child: MaterialApp(theme: buildTheme(), home: Scaffold(body: child)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppState s;

  // setUp runs in a real async context, so plugin-channel awaits complete.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    s = AppState();
    await s.init();
  });

  testWidgets('brief screen renders its header', (tester) async {
    await tester.pumpWidget(_wrap(s, const BriefScreen()));
    await tester.pump();
    expect(find.text("Today's brief"), findsOneWidget);
    expect(find.text('Signal'), findsOneWidget);
  });

  testWidgets('study screen shows its three segments', (tester) async {
    await tester.pumpWidget(_wrap(s, const StudyScreen()));
    await tester.pump();
    expect(find.text('Flashcards'), findsOneWidget);
    expect(find.text('Paper'), findsOneWidget);
    expect(find.text('Goals'), findsOneWidget);
  });

  testWidgets('saved screen shows the empty state', (tester) async {
    await tester.pumpWidget(_wrap(s, const SavedScreen()));
    await tester.pump();
    expect(find.text('Reading list'), findsOneWidget);
    expect(find.textContaining('Nothing saved yet'), findsOneWidget);
  });

  testWidgets('settings screen shows the key sections', (tester) async {
    await tester.pumpWidget(_wrap(s, const SettingsScreen()));
    await tester.pump();
    expect(find.text('Daily time limit'), findsOneWidget);
    expect(find.text('AI features'), findsOneWidget);
    expect(find.text('Daily reminder'), findsOneWidget);
  });

  testWidgets('trends screen renders without trends', (tester) async {
    await tester.pumpWidget(_wrap(s, const TrendsScreen()));
    await tester.pump();
    expect(find.text('Trends'), findsOneWidget);
    expect(find.textContaining('No trends loaded'), findsOneWidget);
  });

  testWidgets('weekly report renders its stats', (tester) async {
    await tester.pumpWidget(_wrap(s, const ReportScreen()));
    await tester.pump();
    expect(find.text('Your week'), findsOneWidget);
    expect(find.text('Top topics'), findsOneWidget);
    expect(find.text('Items read each day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deck is empty until a card is added', (tester) async {
    expect(s.flashcards, isEmpty);
    s.addCard('What is a transformer?', 'An attention-based architecture.');
    expect(s.flashcards, hasLength(1));
    expect(s.dueCards, hasLength(1));
    s.reviewCard(s.flashcards.first, Review.good);
    expect(s.dueCards, isEmpty);
  });

  testWidgets('study screen renders a due review card without layout errors',
      (tester) async {
    s.addCard('What is a transformer?', 'An attention-based architecture.');
    await tester.pumpWidget(_wrap(s, const StudyScreen()));
    await tester.pump();
    expect(find.text('What is a transformer?'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.textContaining('Tap to reveal'), findsOneWidget);
    // Flipping reveals the answer and the rating row.
    await tester.tap(find.text('What is a transformer?'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('An attention-based architecture.'), findsOneWidget);
    expect(find.text('Good'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
