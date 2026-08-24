import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_application_1/models/geofence_site.dart';

class GeofenceService {
  static Future<List<GeofenceSite>> loadSitesForUser(List<String> ids) async {
    if (ids.isEmpty) return [];
    final rows = await Supabase.instance.client
        .from('locations')
        .select()
        .inFilter('id', ids)
        .eq('active', true);
    return rows.map((row) {
      return GeofenceSite(
        id: row['id'].toString(),
        label: row['label']?.toString() ?? 'Duty site',
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        radiusMeters: (row['radius_meters'] as num).toDouble(),
      );
    }).toList();
  }

  static bool isWithinAnySite(LatLng position, List<GeofenceSite> sites) {
    const distance = Distance();
    return sites.any(
      (site) =>
          distance.as(LengthUnit.Meter, position, site.point) <=
          site.radiusMeters,
    );
  }

  static GeofenceSite? nearestSite(LatLng position, List<GeofenceSite> sites) {
    if (sites.isEmpty) return null;
    const distance = Distance();
    GeofenceSite? nearest;
    var best = double.infinity;
    for (final site in sites) {
      final meters = distance.as(LengthUnit.Meter, position, site.point);
      if (meters < best) {
        best = meters;
        nearest = site;
      }
    }
    return nearest;
  }
}
