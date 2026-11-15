import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:earthsync/evidence/features/photo_evidence/photo_evidence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const photoId = 'b20cb742-ddcd-48f8-b457-67b197e90cb2';
const token = 'synthetic-workspace-test-token-12345678';
Uint8List fixture() =>
    File('test/photo_evidence/fixtures/synthetic.png').readAsBytesSync();

Map<String, dynamic> storedJson({String? farmId, String? caption}) => {
  'schema_version': 'evidence.v1',
  'id': photoId,
  'metadata_stripped': true,
  'mime_type': 'image/png',
  'evidence_kind': 'farmer_supplied_photo',
  'caption': caption ?? 'Synthetic field photo',
  'category': 'crop',
  'farmer_observations': 'Synthetic farmer report',
  'captured_date': null,
  'captured_at': null,
  'farm': farmId == null
      ? null
      : {'farm_id': farmId, 'confirmed_by_farmer': true},
};

class FakePicker implements FieldPhotoPicker {
  bool? consent;
  bool cancelled = false;
  @override
  bool get supportsCamera => true;
  @override
  Future<PreparedPhoto?> pick(
    PhotoOrigin origin, {
    required bool readGps,
  }) async {
    consent = readGps;
    if (cancelled) return null;
    return PreparedPhoto(
      png: fixture(),
      origin: origin,
      width: 12,
      height: 8,
      gps: readGps ? const PhotoGps(-33.9, 151.2) : null,
      gpsRequested: readGps,
    );
  }
}

class FakeRepository implements PhotoEvidenceRepository {
  List<StoredPhoto> photos = [];
  PhotoDraft? savedDraft;
  String? replacedId;
  bool fail = false;
  int imageCalls = 0;
  @override
  Future<List<StoredPhoto>> list() async {
    if (fail) {
      throw const PhotoEvidenceException('Evidence service unavailable.');
    }
    return photos.toList();
  }

  @override
  Future<Uint8List> image(String id) async {
    imageCalls++;
    return fixture();
  }

  @override
  Future<void> remove(String id) async =>
      photos.removeWhere((photo) => photo.id == id);
  @override
  Future<StoredPhoto> save(PhotoDraft draft, {String? replaceId}) async {
    savedDraft = draft;
    replacedId = replaceId;
    final photo = StoredPhoto.fromJson(
      storedJson(farmId: draft.farm?.id, caption: draft.caption),
    );
    photos = [photo];
    return photo;
  }
}

Widget harness(
  FakeRepository repository,
  FakePicker picker, {
  bool withFarm = false,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: PhotoEvidencePanel(
        repository: repository,
        picker: picker,
        confirmedFarm: withFarm
            ? ConfirmedFarmReference('synthetic-confirmed-farm')
            : null,
      ),
    ),
  ),
);

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  test(
    'preflight dimensions are bounded without web-unsupported descriptor getters',
    () {
      final png = File(
        'test/photo_evidence/fixtures/synthetic.png',
      ).readAsBytesSync();
      final dimensions = encodedPhotoDimensions(png, png: true);
      expect(dimensions.$1, greaterThan(0));
      final huge = Uint8List.fromList(png);
      ByteData.sublistView(huge).setUint32(16, 8193);
      expect(
        preparePhoto(huge, PhotoOrigin.browserFile, readGps: false),
        throwsA(isA<PhotoEvidenceException>()),
      );
      expect(
        () => encodedPhotoDimensions(
          Uint8List.fromList([255, 216, 255, 217]),
          png: false,
        ),
        throwsA(isA<PhotoEvidenceException>()),
      );
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared v1 response keeps unknown states', () {
    const directory = '../server/tests/evidence/fixtures';
    final fixture = File('$directory/synthetic_v1_photo.json');
    final contents = fixture.readAsStringSync();
    final json = jsonDecode(contents) as Map<String, dynamic>;
    final photo = StoredPhoto.fromJson(json);
    expect(photo.synthetic, isTrue);
    expect(photo.captureLabel, 'Capture date unknown');
    expect(photo.farmId, isNull);
    expect(photo.data['position'], isNull);
    expect(photo.data['quality'], 'not_scientifically_validated');
  });

  test(
    'GPS reader is never called without consent and upload pixels lose metadata',
    () async {
      var calls = 0;
      final prepared = await preparePhoto(
        fixture(),
        PhotoOrigin.gallery,
        readGps: false,
        gpsReader: (_) async {
          calls++;
          return const PhotoGps(-33.9, 151.2);
        },
      );
      expect(calls, 0);
      expect(prepared.gps, isNull);
      expect(
        prepared.png,
        isNot(
          containsAllInOrder(
            utf8.encode('SYNTHETIC private EXIF test metadata'),
          ),
        ),
      );
      expect((prepared.width, prepared.height), (12, 8));
      final consented = await preparePhoto(
        fixture(),
        PhotoOrigin.gallery,
        readGps: true,
        gpsReader: (_) async {
          calls++;
          return const PhotoGps(-33.9, 151.2);
        },
      );
      expect(calls, 1);
      expect(consented.gps?.latitude, -33.9);
      expect(consented.withoutGps().gps, isNull);
    },
  );

  test(
    'consented EXIF GPS is optional and uncertainty stays unknown',
    () async {
      final gps = await readConsentedGps(
        File(
          'test/photo_evidence/fixtures/synthetic_gps.jpg',
        ).readAsBytesSync(),
      );
      expect(gps?.latitude, closeTo(-33.9, 0.00001));
      expect(gps?.longitude, closeTo(151.2, 0.00001));
      expect(gps?.toJson()['uncertainty_m'], isNull);
      expect(await readConsentedGps(fixture()), isNull);
    },
  );

  test(
    'malformed signature and oversized input fail before GPS access',
    () async {
      var calls = 0;
      Future<PhotoGps?> reader(Uint8List _) async {
        calls++;
        return null;
      }

      await expectLater(
        preparePhoto(
          Uint8List.fromList(utf8.encode('<svg/>')),
          PhotoOrigin.browserFile,
          readGps: true,
          gpsReader: reader,
        ),
        throwsA(isA<PhotoEvidenceException>()),
      );
      await expectLater(
        preparePhoto(
          Uint8List(maxPhotoBytes + 1),
          PhotoOrigin.gallery,
          readGps: true,
          gpsReader: reader,
        ),
        throwsA(isA<PhotoEvidenceException>()),
      );
      expect(calls, 0);
    },
  );

  test(
    'unknown dates, unlocated photos and farmer observations survive the contract',
    () {
      final draft = PhotoDraft(
        photo: PreparedPhoto(
          png: fixture(),
          origin: PhotoOrigin.browserFile,
          width: 12,
          height: 8,
        ),
        category: PhotoCategory.water,
        farmerObservations: 'Farmer reports standing water',
      );
      final json = draft.toJson();
      expect(json['source'], 'browser_file');
      expect(json['captured_at'], isNull);
      expect(json['captured_date'], isNull);
      expect(json['capture_time_source'], 'unknown');
      expect(json['farm'], isNull);
      expect(json['position'], isNull);
      expect(json['farmer_observations'], 'Farmer reports standing water');
      final dated = PhotoDraft(
        photo: draft.photo,
        category: draft.category,
        capturedDate: DateTime(2026, 11, 1),
        farm: ConfirmedFarmReference('confirmed'),
      );
      expect(dated.toJson()['captured_date'], '2026-11-01');
      expect(dated.toJson()['captured_at'], isNull);
    },
  );

  test(
    'HTTP upload, unicode metadata, authenticated viewer, replace and remove use v1',
    () async {
      final requests = <http.Request>[];
      final repository = HttpPhotoEvidenceRepository(
        baseUri: Uri.parse('https://evidence.example.org'),
        token: token,
        client: MockClient((request) async {
          requests.add(request);
          expect(request.headers['authorization'], 'Bearer $token');
          if (request.method == 'DELETE') return http.Response('', 204);
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              fixture(),
              200,
              headers: {'content-type': 'image/png'},
            );
          }
          if (request.method == 'GET') {
            return http.Response(jsonEncode([storedJson()]), 200);
          }
          return http.Response(
            jsonEncode(storedJson()),
            request.method == 'POST' ? 201 : 200,
          );
        }),
      );
      final draft = PhotoDraft(
        photo: PreparedPhoto(
          png: fixture(),
          origin: PhotoOrigin.gallery,
          width: 12,
          height: 8,
        ),
        category: PhotoCategory.crop,
        caption: 'စပါး 🌾',
      );
      await repository.save(draft);
      expect(requests.last.url.path, '/api/evidence/v1/photos');
      expect(requests.last.headers['content-type'], 'image/png');
      final metadata = requests.last.headers['x-earthsync-metadata']!;
      expect(metadata.codeUnits.every((unit) => unit <= 127), isTrue);
      expect(jsonDecode(metadata)['caption'], 'စပါး 🌾');
      expect((await repository.list()).single.id, photoId);
      expect(await repository.image(photoId), fixture());
      await repository.save(draft, replaceId: photoId);
      expect(requests.last.method, 'PUT');
      await repository.remove(photoId);
      expect(requests.last.method, 'DELETE');
      await expectLater(
        repository.image('../../private'),
        throwsA(isA<PhotoEvidenceException>()),
      );
    },
  );

  test('service failures never become an empty successful list', () async {
    final repository = HttpPhotoEvidenceRepository(
      baseUri: Uri.parse('http://127.0.0.1:8017'),
      token: token,
      client: MockClient((_) async => http.Response('unavailable', 503)),
    );
    await expectLater(
      repository.list(),
      throwsA(isA<PhotoEvidenceException>()),
    );
    expect(
      () => HttpPhotoEvidenceRepository(
        baseUri: Uri.parse('http://remote.example.org'),
        token: token,
        client: MockClient((_) async => http.Response('', 200)),
      ),
      throwsArgumentError,
    );
    expect(
      () => StoredPhoto.fromJson({
        ...storedJson(),
        'schema_version': 'evidence.v2',
      }),
      throwsFormatException,
    );
  });

  testWidgets(
    'select preview, edit, upload unlocated, view, replace and delete',
    (tester) async {
      final repository = FakeRepository();
      final picker = FakePicker();
      await tester.pumpWidget(harness(repository, picker));
      await tester.pumpAndSettle();
      expect(find.text('No uploaded photos.'), findsOneWidget);
      await tapVisible(tester, find.text('Choose from gallery'));
      expect(picker.consent, isFalse);
      expect(find.text('New photo preview'), findsOneWidget);
      expect(
        find.text('Will be retained as unlocated evidence.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Optional caption'),
        'My crop photo',
      );
      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Your observation (farmer-reported, optional)',
        ),
        'Leaves appear yellow to me',
      );
      await tapVisible(tester, find.text('Upload photo'));
      expect(repository.savedDraft?.farm, isNull);
      expect(repository.savedDraft?.capturedDate, isNull);
      expect(
        repository.savedDraft?.farmerObservations,
        'Leaves appear yellow to me',
      );
      expect(find.text('My crop photo'), findsOneWidget);
      expect(find.text('Unlocated evidence'), findsOneWidget);
      await tapVisible(tester, find.byType(Image).last);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tapVisible(tester, find.byTooltip('Close photo'));
      await tapVisible(tester, find.text('Replace photo'));
      expect(find.text('Replacement photo preview'), findsOneWidget);
      await tapVisible(tester, find.text('Save replacement'));
      expect(repository.replacedId, photoId);
      await tapVisible(tester, find.text('Delete photo'));
      expect(find.text('Delete this photo?'), findsOneWidget);
      await tapVisible(tester, find.text('Cancel'));
      expect(repository.photos, isNotEmpty);
      await tapVisible(tester, find.text('Delete photo'));
      await tapVisible(tester, find.text('Delete'));
      expect(repository.photos, isEmpty);
      expect(find.text('No uploaded photos.'), findsOneWidget);
    },
  );

  testWidgets(
    'EXIF consent can be revoked and farm association needs explicit selection',
    (tester) async {
      final repository = FakeRepository();
      final picker = FakePicker();
      await tester.pumpWidget(harness(repository, picker, withFarm: true));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byType(SwitchListTile));
      await tapVisible(tester, find.text('Choose from gallery'));
      expect(picker.consent, isTrue);
      expect(find.textContaining('Consented EXIF coordinates'), findsOneWidget);
      await tapVisible(tester, find.byType(SwitchListTile));
      expect(find.textContaining('Consented EXIF coordinates'), findsNothing);
      await tapVisible(
        tester,
        find.text(
          'Associate with farmer-confirmed farm synthetic-confirmed-farm',
        ),
      );
      await tapVisible(
        tester,
        find.text('This is a synthetic test image, not a field observation'),
      );
      await tapVisible(tester, find.text('Upload photo'));
      expect(repository.savedDraft?.photo.gps, isNull);
      expect(repository.savedDraft?.farm?.id, 'synthetic-confirmed-farm');
      expect(repository.savedDraft?.synthetic, isTrue);
    },
  );

  testWidgets(
    'cancel selection, discard preview and unavailable service stay explicit',
    (tester) async {
      final repository = FakeRepository();
      final picker = FakePicker()..cancelled = true;
      await tester.pumpWidget(harness(repository, picker));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Take photo'));
      expect(find.text('New photo preview'), findsNothing);
      picker.cancelled = false;
      await tapVisible(tester, find.text('Take photo'));
      await tapVisible(tester, find.text('Remove selected photo'));
      expect(find.text('New photo preview'), findsNothing);
      repository.fail = true;
      await tapVisible(tester, find.byTooltip('Refresh photos'));
      expect(find.text('Evidence service unavailable.'), findsOneWidget);
    },
  );
}
