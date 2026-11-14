import 'dart:convert';

import 'package:flutter/material.dart';

import 'assistant_client.dart';
import 'assistant_models.dart';
import 'l10n/assistant_strings.dart';

/// Embeddable component. 7A can present it in a route or sheet without new state
/// dependencies. A context snapshot is sent only when the farmer asks a question.
class FarmerAssistant extends StatefulWidget {
  const FarmerAssistant({super.key, required this.context, required this.service,
    this.language = 'en'});
  final AssistantContext context;
  final AssistantService service;
  final String language;

  @override
  State<FarmerAssistant> createState() => _FarmerAssistantState();
}

class _Turn {
  const _Turn(this.question, this.answer);
  final String question;
  final AssistantAnswer answer;
}

class _FarmerAssistantState extends State<FarmerAssistant> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _turns = <_Turn>[];
  int _generation = 0;
  bool _loading = false;
  String? _pendingQuestion, _failedQuestion;
  bool _failedExpanded = false;
  AssistantStrings get _strings => AssistantStrings(widget.language);

  @override
  void didUpdateWidget(covariant FarmerAssistant oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (jsonEncode(oldWidget.context.toJson()) != jsonEncode(widget.context.toJson()) ||
        oldWidget.language != widget.language || oldWidget.service != widget.service) {
      ++_generation;
      _turns.clear();
      _loading = false;
      _pendingQuestion = null;
      _failedQuestion = null;
      _input.clear();
    }
  }

  Future<void> _ask(String question, {bool expanded = false}) async {
    final text = question.trim();
    if (_loading || text.isEmpty || text.length > 1000) return;
    final generation = ++_generation;
    setState(() { _loading = true; _pendingQuestion = text; _failedQuestion = null; });
    _input.clear();
    try {
      final answer = await widget.service.ask(question: text, context: widget.context,
        language: widget.language, expanded: expanded);
      if (!mounted || generation != _generation) return;
      if (answer.contextId != widget.context.contextId || answer.language != widget.language) {
        throw const AssistantUnavailable('context_mismatch');
      }
      setState(() {
        _turns.add(_Turn(text, answer));
        // Bound memory in long sessions; previous context is never sent as instructions.
        if (_turns.length > 30) _turns.removeAt(0);
        _loading = false; _pendingQuestion = null;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() { _loading = false; _pendingQuestion = null;
        _failedQuestion = text; _failedExpanded = expanded; });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  void dispose() { ++_generation; _input.dispose(); _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final words = _strings;
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(words('intro')),
          Text(words(widget.context.confirmedFarm == null ? 'noFarm' : 'farm'),
            style: Theme.of(context).textTheme.bodySmall),
        ])),
      Expanded(child: ListView(controller: _scroll, padding: const EdgeInsets.all(12), children: [
        if (_turns.isEmpty && !_loading) Wrap(spacing: 8, runSpacing: 8, children: [
          for (final question in words.questions)
            ActionChip(label: Text(question), onPressed: () => _ask(question)),
        ]),
        for (final turn in _turns) ...[
          Align(alignment: AlignmentDirectional.centerEnd, child: Card(child: Padding(
            padding: const EdgeInsets.all(12), child: Text(turn.question)))),
          _AnswerCard(answer: turn.answer, words: words),
          Align(alignment: AlignmentDirectional.centerStart, child: TextButton(
            onPressed: _loading ? null : () => _ask(turn.question, expanded: true),
            child: Text(words('expanded')))),
        ],
        if (_loading) Semantics(liveRegion: true, child: Column(children: [
          Text(_pendingQuestion ?? ''), const LinearProgressIndicator(), Text(words('loading')),
        ])),
        if (_failedQuestion != null) Semantics(liveRegion: true, child: Column(children: [
          Text(words('error')), TextButton(onPressed: () => _ask(_failedQuestion!, expanded: _failedExpanded),
            child: Text(words('retry'))),
        ])),
      ])),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Row(
        crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: TextField(controller: _input, enabled: !_loading,
          maxLength: 1000, minLines: 1, maxLines: 4,
          textInputAction: TextInputAction.send,
          onSubmitted: (text) => _ask(text), decoration: InputDecoration(
            labelText: words('question'), border: const OutlineInputBorder()))),
        const SizedBox(width: 8),
        IconButton(tooltip: words('send'), onPressed: _loading ? null : () => _ask(_input.text),
          icon: const Icon(Icons.send)),
      ]))),
    ]);
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer, required this.words});
  final AssistantAnswer answer;
  final AssistantStrings words;

  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final claim in answer.claims) Padding(padding: const EdgeInsets.only(bottom: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(words(claim.category.wire), style: Theme.of(context).textTheme.labelMedium),
          SelectableText(claim.text),
          if (claim.sourceIds.isNotEmpty) Text('[${claim.sourceIds.join(', ')}]',
            style: Theme.of(context).textTheme.bodySmall),
        ])),
      if (answer.warnings.isNotEmpty) Text(words('warnings')),
      ExpansionTile(title: Text(words('sources')), children: [
        Text(words('detailsNote')),
        if (answer.citations.isEmpty) Text(words('noSources')),
        // Plain selectable links: no HTML/Markdown execution, link fetching or actions.
        for (final source in answer.citations) ListTile(title: Text('[${source.id}] ${source.provider}'),
          subtitle: SelectableText('${source.title}\n${source.url ?? words('unknown')}')),
        for (final record in answer.evidence) ListTile(title: Text(record.id),
          subtitle: SelectableText(const JsonEncoder.withIndent('  ').convert(record.toJson()))),
        for (final decision in answer.decisions) ListTile(title: Text(decision.scenarioId),
          subtitle: SelectableText(const JsonEncoder.withIndent('  ').convert(decision.toJson()))),
        for (final note in answer.limitations) Text(note),
        for (final warning in answer.warnings) Text(warning),
      ]),
    ])));
}

class FarmerAssistantScreen extends StatelessWidget {
  const FarmerAssistantScreen({super.key, required this.context, required this.service, this.language = 'en'});
  final AssistantContext context;
  final AssistantService service;
  final String language;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(AssistantStrings(language)('title'))),
    body: FarmerAssistant(context: this.context, service: service, language: language));
}
