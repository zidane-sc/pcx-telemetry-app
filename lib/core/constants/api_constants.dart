class ApiConstants {
  // Cloudflare Quick Tunnel URL (or local LAN fallback)
  static const String defaultBaseUrl = 'https://aspects-healing-assist-highlights.trycloudflare.com';
  static const String lanBaseUrl = 'http://192.168.1.53:8092';
  static const String tailscaleBaseUrl = 'http://100.115.78.109:8092';

  // Collections
  static const String collectionVehicles = 'vehicles';
  static const String collectionPreRideScans = 'pre_ride_scans';
  static const String collectionTrips = 'trips';
  static const String collectionDiagnosticTests = 'diagnostic_tests';
  static const String collectionMaintenance = 'maintenance_records';
  static const String collectionAppLogs = 'app_logs';

  // PCX 160 Engine Specs
  static const double pcxDisplacementL = 0.1569; // 156.9cc eSP+ 4-valve
  static const double pcxVolumetricEfficiency = 0.82; // 82% typical stock
  static const double pcxTankCapacityL = 8.1;
  static const double defaultFuelPriceIdr = 13700.0; // Pertamax baseline
}
