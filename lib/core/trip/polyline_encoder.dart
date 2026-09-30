class PolylineEncoder {
  static String encode(List<List<double>> coordinates) {
    final StringBuffer result = StringBuffer();
    int prevLat = 0;
    int prevLng = 0;

    for (final coord in coordinates) {
      if (coord.length < 2) continue;
      final int latE5 = (coord[0] * 1e5).round();
      final int lngE5 = (coord[1] * 1e5).round();

      final int dLat = latE5 - prevLat;
      final int dLng = lngE5 - prevLng;

      prevLat = latE5;
      prevLng = lngE5;

      _encodeValue(dLat, result);
      _encodeValue(dLng, result);
    }

    return result.toString();
  }

  static void _encodeValue(int value, StringBuffer result) {
    int v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      result.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    result.writeCharCode(v + 63);
  }
}
