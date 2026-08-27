import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/health_record.dart';

class FirestoreService {
  FirebaseFirestore? _db;

  FirebaseFirestore get db => _db ??= FirebaseFirestore.instance;

  bool get isAvailable => Firebase.apps.isNotEmpty;

  Future<void> trackLogin({
    required String email,
    required bool successful,
    String? role,
  }) async {
    if (!isAvailable) return;
    await db.collection('login_audit').add({
      'email': email,
      'successful': successful,
      'role': role,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> trackExerciseSubmission({
    required String patientName,
    required int streak,
    required List<String> completedTaskIds,
  }) async {
    if (!isAvailable) return;
    await db.collection('exercise_submissions').add({
      'patientName': patientName,
      'streak': streak,
      'completedTaskIds': completedTaskIds,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> trackEmergency({
    required String patientName,
    required String caregiverRole,
    required double latitude,
    required double longitude,
  }) async {
    if (!isAvailable) return;
    await db.collection('emergency_events').add({
      'patientName': patientName,
      'caregiverRole': caregiverRole,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  DocumentReference<Map<String, dynamic>> _recordRef(String uid) {
    if (!isAvailable) {
      throw FirebaseException(
        plugin: 'firestore',
        code: 'no-app',
        message: 'No Firebase App has been created.',
      );
    }
    return db.collection('health_records').doc(uid);
  }

  Future<void> createOrUpdateHealthRecord(HealthRecord record) async {
    if (!isAvailable) return;
    await _recordRef(record.uid).set(record.toMap(), SetOptions(merge: true));
  }

  Future<HealthRecord?> getHealthRecord(String uid) async {
    if (!isAvailable) return null;
    final snap = await _recordRef(uid).get();
    if (!snap.exists) return null;
    return HealthRecord.fromMap(snap.data()!);
  }

  Stream<HealthRecord?> streamHealthRecord(String uid) {
    if (!isAvailable) {
      return Stream.value(null);
    }

    return _recordRef(uid).snapshots().map((snap) {
      if (!snap.exists) return null;
      return HealthRecord.fromMap(snap.data()!);
    });
  }
}
