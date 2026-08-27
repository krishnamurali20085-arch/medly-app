import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase cloud database service.
/// Replaces MongoDB for syncing all app data to the cloud.
class SupabaseService {
  static SupabaseClient? _client;

  static SupabaseClient get client {
    _client ??= Supabase.instance.client;
    return _client!;
  }

  static bool get isConnected => _client != null;

  /// Test the connection
  static Future<bool> testConnection() async {
    try {
      print('[Supabase] Testing connection...');
      final response = await client.from('users').select('email').limit(1);
      print('[Supabase] Connection successful!');
      return true;
    } catch (e) {
      print('[Supabase] Connection error: $e');
      return false;
    }
  }

  // ---- Generic upsert ----

  static Future<bool> upsert(String table, Map<String, dynamic> data,
      {String? onConflict}) async {
    try {
      await client.from(table).upsert(data);
      print('[Supabase] upsert to $table success');
      return true;
    } catch (e) {
      print('[Supabase] upsert error on $table: $e');
      return false;
    }
  }

  // ---- Find with filter ----

  static Future<List<Map<String, dynamic>>> find(
    String table, {
    Map<String, dynamic>? filter,
    int? limit,
  }) async {
    try {
      var query = client.from(table).select();

      // Apply equality filters one by one
      if (filter != null) {
        for (final entry in filter.entries) {
          query = query.eq(entry.key, entry.value);
        }
      }

      // Apply limit — must use dynamic to avoid type conflict
      dynamic result = query;
      if (limit != null) {
        result = query.limit(limit);
      }

      final response = await result;
      final rows = (response as List).cast<Map<String, dynamic>>();
      print('[Supabase] find returned ${rows.length} rows from $table');
      return rows;
    } catch (e) {
      print('[Supabase] find error on $table: $e');
      return [];
    }
  }

  // ---- Delete ----

  static Future<bool> delete(String table,
      {required Map<String, dynamic> filter}) async {
    try {
      var builder = client.from(table).delete();
      for (final entry in filter.entries) {
        builder = builder.eq(entry.key, entry.value);
      }
      await builder;
      print('[Supabase] delete from $table success');
      return true;
    } catch (e) {
      print('[Supabase] delete error on $table: $e');
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
    String? diseases,
    String? weight,
    String? height,
    String? patientName,
  }) async {
    await upsert('users', {
      'email': email.toLowerCase(),
      'name': name,
      'role': role,
      'password': password,
      'blood_group': bloodGroup,
      'allergies': allergies,
      'diseases': diseases,
      'weight': weight,
      'height': height,
      'patient_name': patientName,
      'synced_at': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncLoginAudit({
    required String email,
    required bool successful,
    String? role,
  }) async {
    await upsert('login_audit', {
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
    int? steps,
  }) async {
    await upsert('health_snapshots', {
      'patient_name': patientName,
      'date_key': dateKey,
      'blood_pressure': bloodPressure,
      'blood_sugar': bloodSugar,
      'heart_rate': heartRate,
      'sleep_hours': sleepHours,
      'steps': steps ?? 0,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> syncSosCall({
    required String patientName,
    String? contactName,
    String? contactPhone,
    double? latitude,
    double? longitude,
  }) async {
    await upsert('sos_log', {
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
    await upsert('sos_locations', {
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
    await upsert('medicine_reminders', {
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
    await upsert('family_members', {
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
    await upsert('family_health_snapshots', {
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
