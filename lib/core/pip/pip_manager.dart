import 'package:floating/floating.dart';

class PipManager {
  static final PipManager _instance = PipManager._internal();
  factory PipManager() => _instance;
  PipManager._internal();

  final Floating _floating = Floating();
  Floating get floating => _floating;

  Future<bool> get isPipAvailable => _floating.isPipAvailable;

  Future<bool> enablePip() async {
    try {
      final available = await _floating.isPipAvailable;
      if (!available) return false;
      final status = await _floating.enable(
        aspectRatio: const Rational.landscape(),
      );
      return status == PiPStatus.enabled;
    } catch (_) {
      return false;
    }
  }
}
