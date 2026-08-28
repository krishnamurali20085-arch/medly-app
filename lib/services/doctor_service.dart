import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class DoctorInfo {
  final String name;
  final String specialty;
  final String phone;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final String address;

  DoctorInfo({
    required this.name,
    required this.specialty,
    required this.phone,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.address,
  });
}

class DoctorService {
  /// Fetch nearby doctors within [radiusKm] kilometers
  static Future<List<DoctorInfo>> fetchNearbyDoctors({double radiusKm = 5}) async {
    try {
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 15),
          ),
        );
      } catch (_) {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) position = lastKnown;
      }
      if (position == null) return [];

      final radius = (radiusKm * 1000).toInt();
      final lat = position.latitude;
      final lon = position.longitude;

      // Query Overpass for doctors, clinics, and hospitals with phone numbers
      final query = '''
[out:json][timeout:25];
(
  node["healthcare"="doctor"](around:$radius,$lat,$lon);
  way["healthcare"="doctor"](around:$radius,$lat,$lon);
  node["amenity"="clinic"](around:$radius,$lat,$lon);
  way["amenity"="clinic"](around:$radius,$lat,$lon);
  node["healthcare"="clinic"](around:$radius,$lat,$lon);
  way["healthcare"="clinic"](around:$radius,$lat,$lon);
  node["amenity"="hospital"](around:$radius,$lat,$lon);
  way["amenity"="hospital"](around:$radius,$lat,$lon);
  node["healthcare"="hospital"](around:$radius,$lat,$lon);
  way["healthcare"="hospital"](around:$radius,$lat,$lon);
);
out center body;
''';

      final servers = [
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
      ];

      http.Response? response;
      for (final server in servers) {
        try {
          response = await http.post(
            Uri.parse(server),
            body: {'data': query},
          ).timeout(const Duration(seconds: 25));
          if (response.statusCode == 200) break;
        } catch (_) {
          continue;
        }
      }

      if (response == null || response.statusCode != 200) return [];

      final data = jsonDecode(response.body);
      final elements = data['elements'] as List? ?? [];
      final doctors = <DoctorInfo>[];

      for (final el in elements) {
        final tags = el['tags'] ?? {};
        final name = tags['name'] ?? tags['operator'] ?? tags['healthcare:speciality'] ?? '';
        if (name.isEmpty || name == 'Unknown') continue;

        final phone = tags['phone'] ?? tags['contact:phone'] ?? tags['addr:phone'] ?? '';
        final addr = tags['addr:full'] ?? tags['addr:street'] ?? tags['addr:city'] ?? '';
        final specialty = tags['healthcare:speciality'] ?? tags['amenity'] ?? 'General';
        final elLat = el['lat'] ?? el['center']?['lat'];
        final elLon = el['lon'] ?? el['center']?['lon'];
        if (elLat == null || elLon == null) continue;

        final dist = Geolocator.distanceBetween(lat, lon, elLat.toDouble(), elLon.toDouble());
        final distKm = dist / 1000;

        doctors.add(DoctorInfo(
          name: name,
          specialty: _formatSpecialty(specialty),
          phone: phone,
          latitude: elLat.toDouble(),
          longitude: elLon.toDouble(),
          distanceKm: distKm,
          address: addr,
        ));
      }

      // Sort by distance
      doctors.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return doctors;
    } catch (e) {
      print('[DoctorService] Error: $e');
      return [];
    }
  }

  static String _formatSpecialty(String raw) {
    final map = {
      'hospital': '🏥 Hospital',
      'clinic': '🩺 Clinic',
      'doctor': '👨‍⚕️ Doctor',
      'pharmacy': '💊 Pharmacy',
      'general_practitioner': '👨‍⚕️ General Practitioner',
      'cardiology': '❤️ Cardiology',
      'dermatology': '🩹 Dermatology',
      'pediatrics': '👶 Pediatrics',
      'orthopedics': '🦴 Orthopedics',
      'ophthalmology': '👁️ Ophthalmology',
      'dentistry': '🦷 Dentistry',
      'gynecology': '妇 Gynecology',
      'neurology': '🧠 Neurology',
      'oncology': '🎗️ Oncology',
      'psychiatry': '🧠 Psychiatry',
      'urology': '泌 Urology',
      'ENT': '👂 ENT',
      'surgery': '🏥 Surgery',
      'radiology': '📡 Radiology',
      'pathology': '🔬 Pathology',
    };
    return map[raw] ?? '🩺 $raw';
  }
}
