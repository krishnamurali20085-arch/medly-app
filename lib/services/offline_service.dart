import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline emergency mode service.
/// Caches critical data locally so SOS works without internet.
class OfflineService {
  // ------- Connectivity check -------

  static Future<bool> isOnline() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ------- Emergency data cache -------

  /// Cache all critical emergency data to SharedPreferences.
  /// Call this whenever the user updates contacts, profile, or health data.
  static Future<void> cacheEmergencyData({
    required String patientName,
    required String bloodGroup,
    required String allergies,
    required String weight,
    required String height,
    required List<Map<String, String>> contacts,
    double? lastLatitude,
    double? lastLongitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('offline_patient_name', patientName);
    await prefs.setString('offline_blood_group', bloodGroup);
    await prefs.setString('offline_allergies', allergies);
    await prefs.setString('offline_weight', weight);
    await prefs.setString('offline_height', height);
    await prefs.setStringList(
      'offline_contacts',
      contacts.map((c) => jsonEncode(c)).toList(),
    );
    if (lastLatitude != null && lastLongitude != null) {
      await prefs.setDouble('offline_lat', lastLatitude);
      await prefs.setDouble('offline_lon', lastLongitude);
    }
    await prefs.setString('offline_cached_at', DateTime.now().toIso8601String());
    print('[Offline] Emergency data cached successfully');
  }

  /// Get cached emergency contacts (works offline).
  static Future<List<Map<String, String>>> getCachedContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('offline_contacts') ?? [];
    return saved.map((s) => Map<String, String>.from(jsonDecode(s))).toList();
  }

  /// Get cached patient info.
  static Future<Map<String, String>> getCachedPatientInfo() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'name': prefs.getString('offline_patient_name') ?? 'Patient',
      'bloodGroup': prefs.getString('offline_blood_group') ?? 'Unknown',
      'allergies': prefs.getString('offline_allergies') ?? 'None',
      'weight': prefs.getString('offline_weight') ?? '',
      'height': prefs.getString('offline_height') ?? '',
    };
  }

  // ------- Offline SOS sync queue -------

  /// Queue an SOS event for syncing when back online.
  static Future<void> queueSosSync({
    required String patientName,
    required String contactName,
    required String contactPhone,
    double? latitude,
    double? longitude,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('offline_sos_queue') ?? [];
    queue.add(jsonEncode({
      'patientName': patientName,
      'contactName': contactName,
      'contactPhone': contactPhone,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': DateTime.now().toIso8601String(),
    }));
    await prefs.setStringList('offline_sos_queue', queue);
    print('[Offline] SOS event queued for sync (${queue.length} pending)');
  }

  /// Get the number of pending SOS syncs.
  static Future<int> getPendingSyncCount() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList('offline_sos_queue') ?? []).length;
  }

  /// Clear the sync queue after successful sync.
  static Future<void> clearSyncQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_sos_queue');
  }

  // ------- Offline healthcare services cache -------

  /// Cache nearby healthcare services for offline access.
  static Future<void> cacheServices(List<Map<String, dynamic>> services) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'offline_services',
      services.map((s) => jsonEncode(s)).toList(),
    );
    await prefs.setString('offline_services_cached_at', DateTime.now().toIso8601String());
  }

  /// Get cached healthcare services.
  static Future<List<Map<String, dynamic>>> getCachedServices() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('offline_services') ?? [];
    return saved.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }
}
