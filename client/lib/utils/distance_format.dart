/// Shared distance formatting for the tracking screens.
///
/// - below 1 km  → "850 m"
/// - 1 km and up → "4.2 km"
/// - [hasGaps]   → " ⚠️" appended; pair it with [kGapWarningText] as the
///   tooltip/subtitle explaining the marker.
String formatDistance(num? km, {bool hasGaps = false}) {
  if (km == null) return '—';
  final base =
      km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';
  return hasGaps ? '$base ⚠️' : base;
}

const String kGapWarningText =
    'tracking was interrupted — actual distance may be higher';
