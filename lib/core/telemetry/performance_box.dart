import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DragState { ready, measuring, finished }

class PerformanceBox extends ChangeNotifier {
  static final PerformanceBox _instance = PerformanceBox._internal();
  factory PerformanceBox() => _instance;
  PerformanceBox._internal();

  DragState _state = DragState.ready;
  DragState get state => _state;

  DateTime? _startTime;
  double _current0to60Sec = 0.0;
  double _best0to60Sec = 0.0;
  double _lastFinishedTimeSec = 0.0;

  double get current0to60Sec => _current0to60Sec;
  double get best0to60Sec => _best0to60Sec;
  double get lastFinishedTimeSec => _lastFinishedTimeSec;

  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _best0to60Sec = prefs.getDouble('best_0_to_60_sec') ?? 0.0;
    } catch (_) {}
    notifyListeners();
  }

  void onSpeedUpdate(double currentSpeedKmh) {
    if (_state == DragState.ready) {
      if (currentSpeedKmh >= 2.0) {
        _state = DragState.measuring;
        _startTime = DateTime.now();
        _current0to60Sec = 0.0;
        notifyListeners();
      }
    } else if (_state == DragState.measuring) {
      if (_startTime != null) {
        final elapsedMs = DateTime.now().difference(_startTime!).inMilliseconds;
        _current0to60Sec = elapsedMs / 1000.0;

        if (currentSpeedKmh >= 60.0) {
          _state = DragState.finished;
          _lastFinishedTimeSec = _current0to60Sec;

          if (_best0to60Sec == 0.0 || _lastFinishedTimeSec < _best0to60Sec) {
            _best0to60Sec = _lastFinishedTimeSec;
            _saveBestRecord(_best0to60Sec);
          }
          notifyListeners();
        } else if (_current0to60Sec > 25.0) {
          // Timeout: rider didn't reach 60 km/h in 25s
          _state = DragState.ready;
          _current0to60Sec = 0.0;
          notifyListeners();
        } else {
          notifyListeners();
        }
      }
    } else if (_state == DragState.finished) {
      if (currentSpeedKmh < 1.0) {
        // Reset to ready when vehicle comes to complete stop at traffic light
        _state = DragState.ready;
        _current0to60Sec = 0.0;
        notifyListeners();
      }
    }
  }

  Future<void> _saveBestRecord(double val) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('best_0_to_60_sec', val);
    } catch (_) {}
  }
}
