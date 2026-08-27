import 'package:mongo_dart/mongo_dart.dart';

/// MongoDB Atlas direct connection service.
class MongoDbService {
  static Db? _db;
  static bool _connected = false;

  // MongoDB Atlas connection string with user's credentials
  static const String _connectionString =
      'mongodb+srv://krishnamurali20085_db_user:KmwzqQs05xb3M1nn@medlycluster.k3npcwh.mongodb.net/?appName=medlycluster';

  static Future<bool> connect() async {
    if (_connected && _db != null && _db!.isConnected) return true;
    try {
      print('[MongoDB] Connecting to Atlas...');
      _db = await Db.create(_connectionString);
      await _db!.open();
      _connected = true;
      print('[MongoDB] Connected successfully!');
      return true;
    } catch (e) {
      print('[MongoDB] Connection error: $e');
      _connected = false;
      return false;
    }
  }

  static Future<Db?> _getDb() async {
    if (_connected && _db != null && _db!.isConnected) return _db;
    final success = await connect();
    if (success) return _db;
    return null;
  }

  static Future<void> disconnect() async {
    try {
      await _db?.close();
      _db = null;
      _connected = false;
    } catch (_) {}
  }

  // ---- Generic CRUD ----

  static Future<bool> insertOne(String collection, Map<String, dynamic> document) async {
    try {
      final db = await _getDb();
      if (db == null) {
        print('[MongoDB] No connection for insertOne');
        return false;
      }
      print('[MongoDB] insertOne collection=$collection');
      await db.collection(collection).insertOne(document);
      print('[MongoDB] insertOne success');
      return true;
    } catch (e) {
      print('[MongoDB] insertOne error: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> find(
    String collection, {
    Map<String, dynamic>? filter,
    int? limit,
  }) async {
    try {
      final db = await _getDb();
      if (db == null) {
        print('[MongoDB] No connection for find');
        return [];
      }
      final coll = db.collection(collection);
      final results = await coll.find(filter).take(limit ?? 1000).toList();
      print('[MongoDB] find returned ${results.length} documents from $collection');
      return results.cast<Map<String, dynamic>>();
    } catch (e) {
      print('[MongoDB] find error: $e');
      return [];
    }
  }

  static Future<bool> updateOne(
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) async {
    try {
      final db = await _getDb();
      if (db == null) return false;
      final coll = db.collection(collection);
      final updateDoc = <String, dynamic>{};
      update.forEach((key, value) {
        updateDoc['\$set'] ??= <String, dynamic>{};
        (updateDoc['\$set'] as Map<String, dynamic>)[key] = value;
      });
      await coll.update(filter, updateDoc);
      print('[MongoDB] updateOne success');
      return true;
    } catch (e) {
      print('[MongoDB] updateOne error: $e');
      return false;
    }
  }

  static Future<bool> deleteOne(String collection, Map<String, dynamic> filter) async {
    try {
      final db = await _getDb();
      if (db == null) return false;
      await db.collection(collection).deleteOne(filter);
      print('[MongoDB] deleteOne success');
      return true;
    } catch (e) {
      print('[MongoDB] deleteOne error: $e');
      return false;
    }
  }

  // ---- High-level sync methods ----

  static Future<void> syncUser({
    required String name,
    required String email,
    required String role,
    required String password,
    String? bloodGroup,
    String? allergies,
    String? weight,
    String? height,
    String? patientName,
  }) async {
    await insertOne('users', {
      'email': email.toLowerCase(),
      'name': name,
      'role': role,
      'password': password,
      'bloodGroup': bloodGroup,
      'allergies': allergies,
      'weight': weight,
      'height': height,
      'patientName': patientName,
      'syncedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncLoginAudit({
    required String email,
    required bool successful,
    String? role,
  }) async {
    await insertOne('login_audit', {
      'email': email,
      'successful': successful,
      'role': role,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncHealthSnapshot({
    required String patientName,
    required String dateKey,
    String? bloodPressure,
    String? bloodSugar,
    String? heartRate,
    String? sleepHours,
  }) async {
    final existing = await find('health_snapshots',
      filter: {'patient_name': patientName, 'date_key': dateKey}, limit: 1);

    if (existing.isNotEmpty) {
      await updateOne('health_snapshots',
        {'patient_name': patientName, 'date_key': dateKey}, {
          'blood_pressure': bloodPressure,
          'blood_sugar': bloodSugar,
          'heart_rate': heartRate,
          'sleep_hours': sleepHours,
          'timestamp': DateTime.now().toIso8601String(),
        });
    } else {
      await insertOne('health_snapshots', {
        'patient_name': patientName,
        'date_key': dateKey,
        'blood_pressure': bloodPressure,
        'blood_sugar': bloodSugar,
        'heart_rate': heartRate,
        'sleep_hours': sleepHours,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  static Future<void> syncSosCall({
    required String patientName,
    String? contactName,
    String? contactPhone,
    double? latitude,
    double? longitude,
  }) async {
    await insertOne('sos_log', {
      'patient_name': patientName,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncSosLocation({
    required double latitude,
    required double longitude,
    String? patientName,
  }) async {
    final now = DateTime.now();
    await insertOne('sos_locations', {
      'latitude': latitude,
      'longitude': longitude,
      'patient_name': patientName,
      'timestamp': now.toIso8601String(),
      'expires_at': now.add(const Duration(hours: 4)).toIso8601String(),
    });
  }

  static Future<void> syncMedicineReminder({
    required String email,
    required String name,
    required String time,
    bool taken = false,
  }) async {
    await insertOne('medicine_reminders', {
      'email': email,
      'name': name,
      'time': time,
      'taken': taken,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncFamilyMember({
    required String caregiverEmail,
    required String patientName,
    String? patientEmail,
    String? relationship,
    String? bloodGroup,
    String? allergies,
    String? weight,
    String? height,
    String? age,
    String? phone,
  }) async {
    await insertOne('family_members', {
      'caregiver_email': caregiverEmail.toLowerCase(),
      'patient_name': patientName,
      'patient_email': patientEmail,
      'relationship': relationship,
      'blood_group': bloodGroup,
      'allergies': allergies,
      'weight': weight,
      'height': height,
      'age': age,
      'phone': phone,
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncFamilyHealthSnapshot({
    required String caregiverEmail,
    required String patientName,
    required String dateKey,
    String? bloodPressure,
    String? bloodSugar,
    String? heartRate,
    String? sleepHours,
    String? notes,
  }) async {
    final existing = await find('family_health_snapshots',
      filter: {'caregiver_email': caregiverEmail.toLowerCase(), 'patient_name': patientName, 'date_key': dateKey}, limit: 1);

    if (existing.isNotEmpty) {
      await updateOne('family_health_snapshots',
        {'caregiver_email': caregiverEmail.toLowerCase(), 'patient_name': patientName, 'date_key': dateKey}, {
          'blood_pressure': bloodPressure,
          'blood_sugar': bloodSugar,
          'heart_rate': heartRate,
          'sleep_hours': sleepHours,
          'notes': notes,
          'timestamp': DateTime.now().toIso8601String(),
        });
    } else {
      await insertOne('family_health_snapshots', {
        'caregiver_email': caregiverEmail.toLowerCase(),
        'patient_name': patientName,
        'date_key': dateKey,
        'blood_pressure': bloodPressure,
        'blood_sugar': bloodSugar,
        'heart_rate': heartRate,
        'sleep_hours': sleepHours,
        'notes': notes,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }
  }

  static Future<bool> testConnection() async {
    try {
      print('[MongoDB] Testing connection...');
      final db = await _getDb();
      if (db == null) return false;
      final count = await db.collection('users').count();
      print('[MongoDB] Test connection successful! Users: $count');
      return true;
    } catch (e) {
      print('[MongoDB] Test connection error: $e');
      return false;
    }
  }

  static bool get isConnected => _connected && _db != null && _db!.isConnected;
}
