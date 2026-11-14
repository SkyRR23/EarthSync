import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'photo_evidence_models.dart';

abstract interface class PhotoEvidenceRepository {
  Future<List<StoredPhoto>> list();
  Future<StoredPhoto> save(PhotoDraft draft, {String? replaceId});
  Future<Uint8List> image(String id);
  Future<void> remove(String id);
}

/// Caller owns HTTP client lifetime and workspace token provisioning.
/// HTTPS is required except for explicit loopback development.
class HttpPhotoEvidenceRepository implements PhotoEvidenceRepository {
  HttpPhotoEvidenceRepository({
    required this.baseUri,
    required this.token,
    required this.client,
  }) {
    if (!baseUri.hasAuthority ||
        baseUri.userInfo.isNotEmpty ||
        baseUri.hasQuery ||
        baseUri.hasFragment ||
        (baseUri.scheme != 'https' &&
            !(baseUri.scheme == 'http' &&
                ['127.0.0.1', 'localhost', '::1'].contains(baseUri.host)))) {
      throw ArgumentError('Use HTTPS or a loopback evidence service URI');
    }
    if (token.length < 32 || token.codeUnits.any((c) => c < 33 || c > 126)) {
      throw ArgumentError('Use a private workspace bearer token');
    }
  }
  final Uri baseUri;
  final String token;
  final http.Client client;
  static const prefix = '/api/evidence/v1';

  Uri _uri(String path) => baseUri.replace(path: '$prefix$path');
  Map<String, String> get _headers => {'Authorization': 'Bearer $token'};
  String _id(String id) {
    if (!RegExp(
      r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
    ).hasMatch(id)) {
      throw const PhotoEvidenceException('Invalid photo identifier.');
    }
    return id;
  }

  Future<http.Response> _response(
    Future<http.Response> request,
    int expected,
  ) async {
    try {
      final response = await request.timeout(const Duration(seconds: 30));
      if (response.statusCode != expected) {
        throw PhotoEvidenceException(switch (response.statusCode) {
          401 => 'Evidence workspace authorization is required.',
          404 => 'Photo no longer exists. Refresh the list.',
          413 => 'Image exceeds the upload limit.',
          415 || 422 =>
            'Photo or metadata was rejected. Choose a JPEG/PNG and check the details.',
          507 => 'Evidence storage is full. Remove an old photo first.',
          _ => 'Evidence service is unavailable. Try again later.',
        });
      }
      return response;
    } on PhotoEvidenceException {
      rethrow;
    } catch (_) {
      throw const PhotoEvidenceException(
        'Could not reach the evidence service.',
      );
    }
  }

  @override
  Future<List<StoredPhoto>> list() async {
    final response = await _response(
      client.get(_uri('/photos'), headers: _headers),
      200,
    );
    return (jsonDecode(utf8.decode(response.bodyBytes)) as List)
        .map((json) => StoredPhoto.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<StoredPhoto> save(PhotoDraft draft, {String? replaceId}) async {
    // HTTP headers are ASCII. Escape UTF-16 code units (including surrogate
    // pairs) so farmer text survives the v1 JSON header without encoding loss.
    final metadata = jsonEncode(draft.toJson()).codeUnits
        .map(
          (unit) => unit > 127
              ? '\\u${unit.toRadixString(16).padLeft(4, '0')}'
              : String.fromCharCode(unit),
        )
        .join();
    if (metadata.length > 8192) {
      throw const PhotoEvidenceException(
        'Photo details exceed 8 KiB. Shorten the caption or observation.',
      );
    }
    final headers = {
      ..._headers,
      'Content-Type': 'image/png',
      'X-EarthSync-Metadata': metadata,
    };
    final uri = _uri(
      replaceId == null ? '/photos' : '/photos/${_id(replaceId)}',
    );
    final response = await _response(
      replaceId == null
          ? client.post(uri, headers: headers, body: draft.photo.png)
          : client.put(uri, headers: headers, body: draft.photo.png),
      replaceId == null ? 201 : 200,
    );
    return StoredPhoto.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
  }

  @override
  Future<Uint8List> image(String id) async => (await _response(
    client.get(_uri('/photos/${_id(id)}/image'), headers: _headers),
    200,
  )).bodyBytes;

  @override
  Future<void> remove(String id) async {
    await _response(
      client.delete(_uri('/photos/${_id(id)}'), headers: _headers),
      204,
    );
  }
}
