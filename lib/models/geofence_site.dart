import 'package:latlong2/latlong.dart';

class GeofenceSite {
  const GeofenceSite({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  LatLng get point => LatLng(latitude, longitude);
}
