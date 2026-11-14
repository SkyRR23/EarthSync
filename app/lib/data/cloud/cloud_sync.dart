import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/farm_boundary.dart';
import '../models/field_analysis.dart';
import '../models/field_note.dart';

/// Firestore layout (rules in app/firestore.rules):
///
///   users/{uid}                 last_seen, platform
///   users/{uid}/farm/main       pin, centre, 4 corners, size, the 3 answers
///   users/{uid}/notes/{noteId}  kind, text, created_at
///   users/{uid}/checks/{auto}   one NASA weather + crop-fit result
///   usage_events/{auto}         event name, time, platform (no uid, no place)
///
/// Every write is fire-and-forget: Firestore queues it offline and sends it
/// when the phone is back online, so the farmer never waits on the network.
class CloudSync {
  CloudSync(this._db, this._auth, {this.storage});

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Null = photos stay on the phone only.
  final FirebaseStorage? storage;

  static String photoPath(String uid, String noteId) =>
      'users/$uid/photos/$noteId.jpg';

  String? get uid => _auth.currentUser?.uid;

  static String get platform => kIsWeb ? 'web' : defaultTargetPlatform.name;

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  void _fire(Future<void> f) => f.catchError((Object e) {
    debugPrint('cloud sync: $e');
  });

  void touchUser() {
    final id = uid;
    if (id == null) return;
    _fire(
      _user(id).set({
        'last_seen': FieldValue.serverTimestamp(),
        'platform': platform,
      }, SetOptions(merge: true)),
    );
  }

  /// The farm: setup pin, 4-corner shape (if marked) and the 3 answers.
  void saveFarm({
    required double? pinLat,
    required double? pinLon,
    required FarmBoundary? farm,
    required String? currentCrop,
    required String? irrigation,
    required String? drainage,
    String? soilTexture,
  }) {
    final id = uid;
    if (id == null || pinLat == null || pinLon == null) return;
    final complete = farm != null && farm.isComplete;
    _fire(
      _user(id).collection('farm').doc('main').set({
        'pin': GeoPoint(pinLat, pinLon),
        'centre': complete
            ? GeoPoint(farm.center.latitude, farm.center.longitude)
            : GeoPoint(pinLat, pinLon),
        // Firestore has no nested arrays, so corners are small maps.
        'corners': complete
            ? [
                for (final c in farm.corners)
                  {'lat': c.latitude, 'lon': c.longitude},
              ]
            : <Object>[],
        'area_m2': complete ? farm.areaM2 : null,
        'area_acres': complete ? farm.areaAcres : null,
        'answers': {
          'current_crop': currentCrop,
          'irrigation': irrigation,
          'drainage': drainage,
          'soil_texture': soilTexture,
        },
        'updated_at': FieldValue.serverTimestamp(),
      }),
    );
  }

  void saveNote(FieldNote n) {
    final id = uid;
    if (id == null) return;
    _fire(
      _user(id).collection('notes').doc(n.id).set({
        'kind': n.kind.name,
        'text': n.text,
        'photo': n.cloudPhoto,
        'created_at': Timestamp.fromDate(n.createdAt),
      }),
    );
  }

  void deleteNote(String noteId) {
    final id = uid;
    if (id == null) return;
    _fire(_user(id).collection('notes').doc(noteId).delete());
    final storage = this.storage;
    if (storage != null) {
      _fire(storage.ref(photoPath(id, noteId)).delete());
    }
  }

  /// Uploads a note photo to the farmer's private folder. Returns its path.
  Future<String?> uploadPhoto(String noteId, File file) async {
    final id = uid;
    final storage = this.storage;
    if (id == null || storage == null || !await file.exists()) return null;
    try {
      final path = photoPath(id, noteId);
      await storage
          .ref(path)
          .putFile(file, SettableMetadata(contentType: 'image/jpeg'));
      return path;
    } catch (e) {
      debugPrint('photo upload failed: $e');
      return null;
    }
  }

  /// One check result: the engine's own numbers and verdicts, unchanged.
  void saveCheck(FieldAnalysis a) {
    final id = uid;
    if (id == null) return;
    final c = a.climateSummary;
    _fire(
      _user(id).collection('checks').add({
        'created_at': FieldValue.serverTimestamp(),
        'location': GeoPoint(a.location.latitude, a.location.longitude),
        'is_demo': a.dataQuality.isDemo,
        'retrieval_mode': a.trace?.retrievalMode,
        'climate': {
          'source_id': c.sourceId,
          'period': c.period,
          'data_kind': c.dataKind,
          'total_rain_mm': c.totalRainMm,
          'mean_temp_c': c.meanTempC,
          'months': [
            for (final m in c.months)
              {
                'year': m.year,
                'month': m.month,
                'rain_mm': m.rainMm,
                'temp_mean_c': m.tempMeanC,
              },
          ],
        },
        'scenarios': [
          for (final s in a.scenarios)
            {
              'id': s.id,
              'is_baseline': s.isBaseline,
              'crops': [for (final st in s.steps) st.cropId],
              'fit': s.eligibility.name,
            },
        ],
        'alerts': [
          for (final al in a.alerts)
            {'hazard': al.hazard, 'level': al.level.name},
        ],
      }),
    );
  }

  /// Anonymous usage count: no user id, no location, no text.
  void logEvent(String event) {
    if (uid == null) return;
    _fire(
      _db.collection('usage_events').add({
        'event': event,
        'at': FieldValue.serverTimestamp(),
        'platform': platform,
      }),
    );
  }

  /// Saved farm (raw map) and notes, used to restore on a new phone.
  Future<({Map<String, dynamic>? farm, List<FieldNote> notes})> load() async {
    final id = uid;
    if (id == null) return (farm: null, notes: const <FieldNote>[]);
    final farmDoc = await _user(id).collection('farm').doc('main').get();
    final notesSnap = await _user(id).collection('notes').get();
    final farm = farmDoc.data();
    final pin = farm?['pin'];
    if (farm != null && pin is GeoPoint) {
      farm['pin'] = {'lat': pin.latitude, 'lon': pin.longitude};
    }
    return (
      farm: farm,
      notes: [
        for (final d in notesSnap.docs)
          FieldNote(
            id: d.id,
            createdAt:
                (d.data()['created_at'] as Timestamp?)?.toDate() ??
                DateTime.now(),
            kind: NoteKind.values.firstWhere(
              (k) => k.name == d.data()['kind'],
              orElse: () => NoteKind.other,
            ),
            text: d.data()['text'] as String? ?? '',
            cloudPhoto: d.data()['photo'] as String?,
          ),
      ],
    );
  }
}

/// Google sign-in through Firebase (browser flow; no extra plugin needed).
Future<User?> signInWithGoogle(FirebaseAuth auth) async {
  final provider = GoogleAuthProvider()
    ..setCustomParameters({'prompt': 'select_account'});
  final cred = kIsWeb
      ? await auth.signInWithPopup(provider)
      : await auth.signInWithProvider(provider);
  return cred.user;
}
