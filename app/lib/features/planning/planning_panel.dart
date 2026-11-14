import '../../app/ui_labels.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/ui_copy.dart';
import '../../design/components/product.dart';
import '../../state/home_provider.dart';

/// Farmer notes are retained separately from versioned engine inputs. Recording
/// a crop or a system never creates an agricultural rule or recommendation.
final farmNotesProvider = FutureProvider.autoDispose
    .family<Map<String, String>, String>((ref, id) async {
      final store = await SharedPreferences.getInstance();
      final raw = store.getString('farm.notes.$id');
      if (raw == null) return {};
      return Map<String, String>.from(jsonDecode(raw) as Map);
    });

class PlanningPanel extends ConsumerWidget {
  const PlanningPanel({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ref.watch(homeProfileProvider).value?.farm?.id;
    if (id == null) return const SizedBox.shrink();
    return ref
        .watch(farmNotesProvider(id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (_, _) => EvidenceNotice(
            title: UiLabels.savedCropNotesUnavailable,
            message: UiLabels.tryLoadingYourNotesAgainExistingNotesHave,
            action: TextButton(
              onPressed: () => ref.invalidate(farmNotesProvider(id)),
              child: const Text(UiLabels.retryNotes),
            ),
          ),
          data: (notes) =>
              _PlanningForm(key: ValueKey(id), id: id, notes: notes),
        );
  }
}

class _PlanningForm extends StatefulWidget {
  const _PlanningForm({super.key, required this.id, required this.notes});
  final String id;
  final Map<String, String> notes;
  @override
  State<_PlanningForm> createState() => _PlanningFormState();
}

class _PlanningFormState extends State<_PlanningForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _fields;
  static const keys = [
    'previous',
    'previousStart',
    'previousEnd',
    'current',
    'currentStart',
    'currentEnd',
    'productionSystem',
    'irrigation',
    'drainage',
    'priorities',
  ];
  bool _saving = false;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _fields = {
      for (final key in keys)
        key: TextEditingController(text: widget.notes[key] ?? ''),
    };
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String tr(String k) => UiCopy.text(context, k);
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _notice = null;
    });
    try {
      final store = await SharedPreferences.getInstance();
      final ok = await store.setString(
        'farm.notes.${widget.id}',
        jsonEncode({
          for (final e in _fields.entries) e.key: e.value.text.trim(),
        }),
      );
      if (!ok) throw StateError(UiLabels.saveFailed);
      if (mounted) setState(() => _notice = tr('saved'));
    } catch (_) {
      if (mounted) {
        setState(() => _notice = UiLabels.couldNotSaveCropNotesPleaseTryAgain);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _input(String key, String label, {bool date = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: _fields[key],
      enabled: !_saving,
      maxLength: date ? 10 : 160,
      decoration: InputDecoration(
        labelText: label,
        hintText: date ? 'YYYY-MM-DD' : null,
        suffixIcon: date
            ? IconButton(
                tooltip: label,
                onPressed: _saving
                    ? null
                    : () async {
                        final day = await showDatePicker(
                          context: context,
                          initialDate:
                              DateTime.tryParse(_fields[key]!.text) ??
                              DateTime.now(),
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2100),
                        );
                        if (day != null && mounted) {
                          setState(
                            () => _fields[key]!.text = day
                                .toIso8601String()
                                .substring(0, 10),
                          );
                        }
                      },
                icon: const Icon(Icons.calendar_today_outlined),
              )
            : null,
      ),
      onChanged: (_) => setState(() => _notice = null),
      validator: (text) {
        if (!date || text == null || text.trim().isEmpty) return null;
        final d = DateTime.tryParse(text.trim());
        if (d == null || d.toIso8601String().substring(0, 10) != text.trim()) {
          return UiLabels.enterAnExactDateAsYYYYMMDD;
        }
        if (key.endsWith('End')) {
          final start = DateTime.tryParse(
            _fields[key.replaceFirst('End', 'Start')]!.text,
          );
          if (start != null && d.isBefore(start)) {
            return UiLabels.harvestMustFollowPlanting;
          }
        }
        return null;
      },
    ),
  );
  String _dateLabel(String key) {
    final value = _fields[key]!.text.trim();
    return value.isEmpty ? UiLabels.dateUnknown : value;
  }

  String _periodLabel(String key) {
    if (_fields['${key}Start']!.text.trim().isEmpty &&
        _fields['${key}End']!.text.trim().isEmpty) {
      return UiLabels.datesNotRecorded;
    }
    return UiLabels.cropPeriod(
      _dateLabel('${key}Start'),
      _dateLabel('${key}End'),
    );
  }

  Widget _timeline(String key, IconData icon) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(
      _fields[key]!.text.trim().isEmpty
          ? tr('unknownCrop')
          : _fields[key]!.text,
    ),
    subtitle: Text('${tr(key)} · ${_periodLabel(key)}'),
  );
  @override
  Widget build(BuildContext context) => SectionCard(
    title: tr('history'),
    icon: Icons.timeline,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(tr('historyBody')),
          _timeline('previous', Icons.history),
          const Divider(),
          _timeline('current', Icons.spa_outlined),
          ExpansionTile(
            title: const Text(UiLabels.recordCropHistoryFarmContext),
            children: [
              _input('previous', tr('previous')),
              ResponsivePair(
                first: _input(
                  'previousStart',
                  UiLabels.previousPlantingDate,
                  date: true,
                ),
                second: _input(
                  'previousEnd',
                  UiLabels.previousHarvestDate,
                  date: true,
                ),
              ),
              _input('current', tr('current')),
              ResponsivePair(
                first: _input('currentStart', tr('dateStart'), date: true),
                second: _input('currentEnd', tr('dateEnd'), date: true),
              ),
              _input('productionSystem', UiLabels.productionSystemOptional),
              _input('irrigation', UiLabels.irrigationOptional),
              _input('drainage', UiLabels.drainageOptional),
              _input('priorities', UiLabels.farmerPrioritiesOptional),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Saving…' : UiLabels.saveCropNotes),
              ),
            ],
          ),
          if (_notice != null)
            Semantics(liveRegion: true, child: Text(_notice!)),
          const SizedBox(height: 12),
          const Text(UiLabels.theseNotesAreNotAutomaticallySuppliedToRust),
        ],
      ),
    ),
  );
}
