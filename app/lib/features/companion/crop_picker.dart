import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/platform_farms.dart';
import '../../data/platform_transport.dart';
import '../../state/journal_provider.dart';
import '../../state/platform_provider.dart';
import 'companion_copy.dart';

Future<Map<String, dynamic>?> pickCatalogCrop(BuildContext context) =>
    showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CropPicker(),
    );

class _CropPicker extends ConsumerStatefulWidget {
  const _CropPicker();
  @override
  ConsumerState<_CropPicker> createState() => _CropPickerState();
}

class _CropPickerState extends ConsumerState<_CropPicker> {
  final _query = TextEditingController();
  List<Map<String, dynamic>> _options = [];
  bool _busy = false;
  String? _notice;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    final client = ref.read(platformFarmClientProvider);
    final cache = ref.read(journalCacheProvider);
    final query = _query.text.trim();
    final key =
        'earthsync.crop-options.v1.${client?.transport.baseUri.origin}.${Uri.encodeComponent(query)}';
    try {
      if (client == null) throw const PlatformFailure('NETWORK_UNAVAILABLE');
      final value = Map<String, dynamic>.from(
        await client.transport.request(
              'GET',
              '${PlatformFarmClient.prefix}/crop-options?${Uri(queryParameters: {'q': query}).query}',
              expectedStatus: 200,
            )
            as Map,
      );
      await cache.save(key, {
        'result': value,
        'retrieved_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(
          () => _options = List<Map<String, dynamic>>.from(
            value['crops'] as List,
          ),
        );
      }
    } catch (error) {
      final saved =
          error is PlatformFailure && error.code == 'NETWORK_UNAVAILABLE'
          ? await cache.read(key)
          : null;
      if (mounted) {
        setState(() {
          _options = saved == null
              ? []
              : List<Map<String, dynamic>>.from(
                  saved['result']['crops'] as List,
                );
          _notice = saved == null
              ? 'Crop catalog unavailable. Keep the crop unknown or use a farmer-reported name.'
              : 'Cached reference list · retrieved ${saved['retrieved_at']}';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(CompanionCopy.text(context, 'Crop references')),
    content: SizedBox(
      width: 560,
      height: 440,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _query,
            maxLength: 150,
            decoration: InputDecoration(
              labelText: CompanionCopy.text(context, 'Search crops or aliases'),
            ),
            onSubmitted: _busy ? null : (_) => _search(),
          ),
          TextButton(
            onPressed: _busy ? null : _search,
            child: Text(CompanionCopy.text(context, 'Search')),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_notice != null) Text(_notice!),
          Expanded(
            child: ListView(
              children: [
                for (final c in _options)
                  ListTile(
                    title: Text((c['aliases'] as List).take(3).join(' · ')),
                    subtitle: Text(
                      '${c['scientific_name']} · reference identity only',
                    ),
                    onTap: _busy ? null : () => Navigator.pop(context, c),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );
}
