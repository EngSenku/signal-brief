import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../ai.dart';
import '../feeds.dart';
import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../widgets.dart';
import 'item.dart';
import 'report.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController key =
      TextEditingController(text: context.read<AppState>().nvidiaKey);
  bool revealKey = false;
  bool testing = false;
  String? testMsg;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 120),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('Settings',
              style: TextStyle(fontSize: 36, fontWeight: FontWeight.w300)),
        ),
        const SizedBox(height: 20),

        // Time limit
        Section(
          title: 'Daily time limit',
          sub: st.budgetMin == 0
              ? 'Off — no lock screen'
              : '${st.budgetMin} min per day · used ${(st.usedSec / 60).floor()} min today',
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: C.lime,
              thumbColor: C.lime,
              inactiveTrackColor: const Color(0x22FFFFFF),
              overlayColor: Colors.transparent,
            ),
            child: Slider(
              value: st.budgetMin.toDouble(),
              min: 0,
              max: 120,
              divisions: 24,
              label: '${st.budgetMin}',
              onChanged: (v) => st.setBudget(v.round()),
            ),
          ),
        ),

        // Reminder
        Section(
          title: 'Daily reminder',
          sub: 'One notification a day when your digest is ready. No other pings.',
          child: Column(children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: C.lime,
              title: const Text('Remind me daily'),
              value: st.notifyEnabled,
              onChanged: (v) async {
                await st.setReminder(v);
                if (!context.mounted) return;
                if (v) {
                  showSnack(context, 'Daily reminder set for ${st.notifyTime.format(context)}');
                }
              },
            ),
            if (st.notifyEnabled)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Time'),
                trailing: Text(st.notifyTime.format(context),
                    style: const TextStyle(color: C.lime)),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: st.notifyTime,
                    builder: (c, child) => Theme(
                      data: Theme.of(c).copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: C.lime,
                          surface: C.surface,
                          onPrimary: Colors.black,
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (t != null) await st.setReminder(true, time: t);
                },
              ),
          ]),
        ),

        // AI
        Section(
          title: 'AI features',
          sub: 'Powered by your NVIDIA API key. The key is stored in the '
              'device keychain, never leaves the phone except to call NVIDIA.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: key,
              obscureText: !revealKey,
              onChanged: st.setKey,
              decoration: InputDecoration(
                hintText: 'nvapi-…',
                hintStyle: const TextStyle(color: C.muted),
                suffixIcon: IconButton(
                  icon: Icon(
                      revealKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: C.muted),
                  onPressed: () => setState(() => revealKey = !revealKey),
                ),
                filled: true,
                fillColor: C.faint,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            const Text('Model', style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: C.faint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: kAiModels.containsKey(st.aiModel) ? st.aiModel : kDefaultModel,
                  isExpanded: true,
                  dropdownColor: C.surface,
                  icon: const Icon(Icons.expand_more_rounded, color: C.muted),
                  items: [
                    for (final e in kAiModels.entries)
                      DropdownMenuItem(
                        value: e.key,
                        child: Text(e.key,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                  onChanged: (v) => v == null ? null : st.setModel(v),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(kAiModels[st.aiModel] ?? '',
                  style: const TextStyle(color: C.muted, fontSize: 12)),
            ),
            const SizedBox(height: 12),
            Row(children: [
              PillButton('Test key',
                  icon: Icons.bolt_rounded, busy: testing, onTap: _test),
            ]),
            if (testMsg != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(testMsg!,
                    style: TextStyle(
                        color: testMsg!.startsWith('OK') ? C.lime : C.yellow)),
              ),
          ]),
        ),

        // Boost
        Section(
          title: 'Boost topics',
          sub: 'Items mentioning these rank higher in the brief.',
          child: _Keywords(
              list: st.boost,
              hint: 'Add a topic',
              onChanged: (l) => st.setList('boost', l)),
        ),

        // Mute
        Section(
          title: 'Muted words',
          sub: 'Items mentioning these never appear.',
          child: _Keywords(
              list: st.mute,
              hint: 'Add a word to hide',
              onChanged: (l) => st.setList('mute', l)),
        ),

        // Report
        Section(
          title: 'Weekly report',
          sub: 'See what you read and learned this week.',
          child: Align(
            alignment: Alignment.centerLeft,
            child: PillButton('Open report',
                icon: Icons.insights_rounded,
                filled: true,
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ReportScreen()))),
          ),
        ),

        // Sources
        Section(
          title: 'Sources',
          sub: '${kSources.length - st.disabled.length} of ${kSources.length} active. '
              'Changes apply on the next refresh.',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final group in _groupedSources()) ...[
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 2),
                child: Text(group.key,
                    style: const TextStyle(
                        color: C.lime,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4)),
              ),
              for (final s in group.value)
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: C.lime,
                  title: Text(s.name),
                  subtitle: Text(
                      s.about == null ? s.cat : '${s.cat} · ${s.about}',
                      style: const TextStyle(color: C.muted, fontSize: 12)),
                  value: !st.disabled.contains(s.name),
                  onChanged: (_) => st.toggleSource(s.name),
                ),
            ],
          ]),
        ),

        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Center(
            child: Text('Signal · your finite, filtered, intentional feed',
                style: TextStyle(color: C.muted, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  List<MapEntry<String, List<Source>>> _groupedSources() {
    final groups = <String, List<Source>>{};
    for (final s in kSources) {
      (groups[s.cat] ??= <Source>[]).add(s);
    }
    const order = ['AI', 'Dev', 'Research', 'News', 'Video', 'Sport', 'Anime', 'Morocco'];
    final entries = groups.entries.toList()
      ..sort((a, b) {
        final ia = order.indexOf(a.key);
        final ib = order.indexOf(b.key);
        return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      });
    return entries;
  }

  Future<void> _test() async {
    setState(() {
      testing = true;
      testMsg = null;
    });
    final st = context.read<AppState>();
    try {
      final reply = await NvidiaClient(apiKey: st.nvidiaKey, model: st.aiModel)
          .complete([
        {
          'role': 'system',
          'content': 'You are a connectivity check. Answer with a single word.'
        },
        {'role': 'user', 'content': 'Reply with exactly: OK'}
      ], maxTokens: 200, temperature: 0);
      setState(() => testMsg = 'OK — ${reply.trim().split('\n').first}');
    } catch (e) {
      setState(() => testMsg = aiMessage(e));
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }
}

class _Keywords extends StatefulWidget {
  const _Keywords(
      {required this.list, required this.hint, required this.onChanged});
  final List<String> list;
  final String hint;
  final ValueChanged<List<String>> onChanged;
  @override
  State<_Keywords> createState() => _KeywordsState();
}

class _KeywordsState extends State<_Keywords> {
  final c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (widget.list.isNotEmpty)
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in widget.list)
            TagChip(k,
                onDeleted: () =>
                    widget.onChanged(widget.list.where((e) => e != k).toList())),
        ]),
      const SizedBox(height: 10),
      TextField(
        controller: c,
        onSubmitted: (v) {
          final t = v.trim().toLowerCase();
          if (t.isNotEmpty && !widget.list.contains(t)) {
            widget.onChanged([...widget.list, t]);
          }
          c.clear();
        },
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: C.muted),
          filled: true,
          fillColor: C.faint,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
        ),
      ),
    ]);
  }
}
