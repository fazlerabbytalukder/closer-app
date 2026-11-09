import 'dart:async';

import 'package:closer_app/core/models/models.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// Current position + a readable place name for location sends.
abstract final class LocationService {
  /// Makes sure Location is on and permitted, prompting if needed.
  /// Throws a [CloserException] with a user-facing message otherwise.
  static Future<void> ensureReady() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      unawaited(Geolocator.openLocationSettings());
      throw const CloserException('Turn on Location, then try again.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      unawaited(Geolocator.openAppSettings());
      throw const CloserException('Allow Location for Closer in Settings to send where you are.');
    }
    if (perm == LocationPermission.denied) {
      throw const CloserException('Location permission is needed to send where you are.');
    }
  }

  /// Where the user is now. Call [ensureReady] first.
  static Future<GeoTag> current() async {
    final Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null) throw const CloserException('Couldn’t find your location. Try again outside or near a window.');
      return GeoTag(lat: last.latitude, lng: last.longitude, place: await _place(last.latitude, last.longitude));
    }
    return GeoTag(lat: pos.latitude, lng: pos.longitude, place: await _place(pos.latitude, pos.longitude));
  }

  /// "Gulshan, Dhaka, Bangladesh" — empty when offline / no geocoder.
  static Future<String> _place(double lat, double lng) async {
    try {
      final marks = await Geocoding().placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 8));
      if (marks.isEmpty) return '';
      final p = marks.first;
      final parts = <String>[];
      for (final s in [p.subLocality, p.locality ?? p.subAdministrativeArea, p.country]) {
        final v = s?.trim() ?? '';
        if (v.isNotEmpty && !parts.contains(v)) parts.add(v);
      }
      final place = parts.join(', ');
      return place.length > GeoTag.maxPlace ? place.substring(0, GeoTag.maxPlace) : place;
    } on Object {
      return '';
    }
  }
}
