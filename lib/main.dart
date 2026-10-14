import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';

import 'screens/brief.dart';
import 'screens/saved.dart';
import 'screens/settings.dart';
import 'screens/study.dart';
import 'screens/trends.dart';
import 'services/sharing.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // `.env` is gitignored; a clone without it still runs, just with no AI key.
  try {
    await dotenv.load();
  } catch (_) {}
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: C.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const SignalApp()));
}

class SignalApp extends StatelessWidget {
  const SignalApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Signal',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> with WidgetsBindingObserver {
  int tab = 0;
  Timer? _timer;
  final _sharing = Sharing();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final st = context.read<AppState>();
    st.notifications.onOpenBrief = () {
      if (mounted) setState(() => tab = 0);
    };
    _start();
    st.refreshIfStale();
    st.refreshTrendsIfStale();
    _sharing.init(_onShared);
  }

  Future<void> _onShared(List<String> texts) async {
    final st = context.read<AppState>();
    final n = await st.addShared(texts);
    if (!mounted) return;
    setState(() => tab = 3); // jump to the reading list
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(n > 0
            ? 'Added $n ${n == 1 ? 'link' : 'links'} to your reading list.'
            : 'That link is already in your reading list.'),
      ));
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(
        const Duration(seconds: 1), (_) => context.read<AppState>().tick());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) {
      _start();
      context.read<AppState>().refreshIfStale();
    } else {
      _timer?.cancel();
      context.read<AppState>().persistUsage();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sharing.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Scaffold(
      body: Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(1.0, -1.0),
                radius: 1.1,
                colors: [Color(0x30E6D84A), Color(0x00E6D84A)],
              ),
            ),
          ),
        ),
        SafeArea(
          bottom: false,
          child: IndexedStack(
            index: tab,
            children: const [
              BriefScreen(),
              TrendsScreen(),
              StudyScreen(),
              SavedScreen(),
              SettingsScreen(),
            ],
          ),
        ),
        if (st.locked && tab != 4)
          Positioned.fill(
            child: Container(
              color: C.bg,
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.nightlight_round, size: 44, color: C.lime),
                const SizedBox(height: 20),
                const Text("That's your time for today",
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w300),
                    textAlign: TextAlign.center),
                const SizedBox(height: 10),
                Text(
                    'You used your ${st.budgetMin} minutes. Close the app and go build something.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: C.muted, height: 1.4)),
                const SizedBox(height: 28),
                PillButton('I need 5 more minutes', onTap: st.extend),
              ]),
            ),
          ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 12,
          child: SafeArea(
            top: false,
            child: _NavBar(
                index: tab, onTap: (i) => setState(() => tab = i)),
          ),
        ),
      ]),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  static const _items = [
    (Icons.grid_view_rounded, 'Brief'),
    (Icons.trending_up_rounded, 'Trends'),
    (Icons.school_rounded, 'Study'),
    (Icons.bookmark_rounded, 'Saved'),
    (Icons.tune_rounded, 'You'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xF2151613),
        borderRadius: BorderRadius.circular(34),
        border: Border.all(color: C.line),
        boxShadow: const [
          BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 8)),
        ],
      ),
      child: Row(children: [
        for (var i = 0; i < _items.length; i++)
          Expanded(
            child: GestureDetector(
              onTap: () => onTap(i),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
                decoration: BoxDecoration(
                  color: index == i ? C.lime : Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_items[i].$1,
                        size: 20,
                        color: index == i ? Colors.black : C.muted),
                    if (index == i) ...[
                      const SizedBox(width: 5),
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(_items[i].$2,
                              maxLines: 1,
                              style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
