import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class RouteInfo {
  final List<LatLng> points;
  final double distanceMeters;
  final int durationSeconds;
  final String summary;

  RouteInfo({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.summary,
  });

  String get distanceText {
    if (distanceMeters < 1000) return '${distanceMeters.round()} m';
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get durationText {
    final mins = durationSeconds ~/ 60;
    if (mins < 60) return '$mins min';
    final hrs = mins ~/ 60;
    final remainMins = mins % 60;
    return '$hrs hr ${remainMins} min';
  }
}

class RoutingService {
  /// Fetch driving route from [origin] to [destination] using OSRM
  static Future<RouteInfo?> getRoute(LatLng origin, LatLng destination) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}'
        '?overview=full&geometries=geojson&steps=true';

    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'Medly/1.0'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) return null;

      final route = data['routes'][0];
      final geometry = route['geometry'];
      final coords = geometry['coordinates'] as List;

      // Decode GeoJSON coordinates to LatLng
      final points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

      // Get summary from legs
      String summary = '';
      final legs = route['legs'] as List?;
      if (legs != null && legs.isNotEmpty) {
        summary = legs[0]['summary'] ?? '';
      }

      return RouteInfo(
        points: points,
        distanceMeters: (route['distance'] as num).toDouble(),
        durationSeconds: (route['duration'] as num).toInt(),
        summary: summary,
      );
    } catch (e) {
      print('[RoutingService] Error: $e');
      return null;
    }
  }
}
