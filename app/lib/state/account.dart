import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/strings.dart';
import '../data/cloud/cloud_sync.dart';
import 'providers.dart';

/// Firebase Auth, or null when Firebase did not start (tests / no config).
final authProvider = Provider<FirebaseAuth?>((ref) => null);

/// The signed-in Google user (null = signed out or no Firebase).
final userProvider = StreamProvider<User?>((ref) {
  final auth = ref.watch(authProvider);
  return auth == null ? Stream.value(null) : auth.authStateChanges();
});

/// Google sign-in, then sync both ways: restore a saved farm and notes on a
/// new phone, and upload what this phone already has. Returns an error
/// message for the farmer, or null on success.
Future<String?> signInAndSync(WidgetRef ref) async {
  final auth = ref.read(authProvider);
  final sync = ref.read(cloudSyncProvider);
  if (auth == null || sync == null) return S.cloudUnavailable;
  try {
    final user = await signInWithGoogle(auth);
    if (user == null) return S.signInFailed;
  } on FirebaseAuthException catch (e) {
    if (e.code == 'canceled' || e.code == 'web-context-canceled') return null;
    debugPrint('Google sign-in failed: ${e.code} ${e.message}');
    return S.signInFailed;
  } catch (e) {
    debugPrint('Google sign-in failed: $e');
    return S.signInFailed;
  }
  sync.touchUser();
  try {
    final saved = await sync.load();
    final draft = ref.read(farmerDraftProvider.notifier);
    if (saved.farm != null) draft.restoreFromCloud(saved.farm!);
    draft.pushToCloud();
    ref.read(notesProvider.notifier).mergeCloud(saved.notes);
  } catch (_) {
    // Offline: uploads are queued by Firestore; restore can happen later.
  }
  return null;
}

Future<void> signOut(WidgetRef ref) async => ref.read(authProvider)?.signOut();
