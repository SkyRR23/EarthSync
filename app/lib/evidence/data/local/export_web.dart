import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<String> saveFarmExport(String contents) async {
  final blob = web.Blob(
    [contents.toJS].toJS,
    web.BlobPropertyBag(type: 'application/json'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download =
        'EarthSync-farm-export-${DateTime.now().microsecondsSinceEpoch}.json';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
    const Duration(seconds: 5),
    () => web.URL.revokeObjectURL(url),
  );
  return 'Your browser download folder';
}
