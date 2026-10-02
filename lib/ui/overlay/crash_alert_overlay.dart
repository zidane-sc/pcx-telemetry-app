import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/audio/voice_alert_service.dart';
import '../../core/telemetry/crash_detector.dart';
import '../../core/telemetry/ride_report_service.dart';

/// Full-screen crash countdown.
///
/// The rider has [CrashDetector.countdownSeconds] to confirm they are OK. This
/// screen exists to be unmissable and loud, because a rider who is concussed
/// cannot tap a small button.
///
/// **It never sends anything by itself.** Expiry logs the event and offers the
/// SMS composer, which the rider must still press send on. An automatic
/// emergency message sent from a moving motorcycle on a false positive is worse
/// than a missed call: it tells someone's family member that a crash happened
/// when it did not.
class CrashAlertOverlay extends StatefulWidget {
  final CrashDetection detection;
  final VoidCallback onCancel;
  final VoidCallback onExpired;

  const CrashAlertOverlay({
    super.key,
    required this.detection,
    required this.onCancel,
    required this.onExpired,
  });

  /// Returns a future that completes when the dialog is dismissed, so the caller
  /// can gate further crash alerts until then.
  static Future<void> show(
    BuildContext context, {
    required CrashDetection detection,
    required VoidCallback onCancel,
    required VoidCallback onExpired,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (_) => CrashAlertOverlay(
        detection: detection,
        onCancel: onCancel,
        onExpired: onExpired,
      ),
    );
  }

  @override
  State<CrashAlertOverlay> createState() => _CrashAlertOverlayState();
}

class _CrashAlertOverlayState extends State<CrashAlertOverlay> {
  late int _remaining = CrashDetector.countdownSeconds;
  Timer? _timer;
  bool _expired = false;

  @override
  void initState() {
    super.initState();

    // The first three seconds are the panic window: say it, loudly, on the
    // default channel so it is heard over music.
    VoiceAlertService().speakAlert(
      'Kecelakaan terdeteksi. Saya baik-baik saja.',
      cooldownSeconds: 0,
      alertKey: 'crash_initial',
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_remaining <= 1) {
        t.cancel();
        setState(() => _expired = true);
        widget.onExpired();
      } else {
        setState(() => _remaining -= 1);
        VoiceAlertService().speakAlert(
          '$_remaining detik. Ketuk tombol hijau jika Anda baik-baik saja.',
          cooldownSeconds: 0,
          alertKey: 'crash_countdown_$_remaining',
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contact = RideReportService().emergencyContact;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  color: Colors.redAccent, size: 72),
              const SizedBox(height: 16),
              const Text(
                'KECELAKAAN TERCURIGA',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Guncangan ${widget.detection.peakG.toStringAsFixed(1)} g terdeteksi. '
                'Ketuk tombol hijau bila Anda aman.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 32),

              if (!_expired)
                Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.redAccent, width: 4),
                  ),
                  child: Center(
                    child: Text(
                      '$_remaining',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 68,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),

              if (_expired) ...[
                const Text(
                  'Waktu habis. Tidak ada pesan yang dikirim otomatis.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (contact.isNotEmpty)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.sms, size: 18),
                    label: Text('Kirim SMS ke $contact'),
                    onPressed: () async {
                      await RideReportService().openEmergencySms(
                        'Saya zeta, terjadi kecelakaan. '
                        'Lokasi terakhir: ${widget.detection.peakG.toStringAsFixed(1)} g. '
                        'Mohon cek.',
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.amber,
                      side: const BorderSide(color: Colors.amber),
                    ),
                  ),
              ],

              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 74,
                child: ElevatedButton(
                  onPressed: () {
                    _timer?.cancel();
                    VoiceAlertService().speakAlert(
                      'Dibatalkan. Hope you are safe riding.',
                      cooldownSeconds: 0,
                      alertKey: 'crash_cancel',
                    );
                    widget.onCancel();
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00FF66),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'SAYA AMAN',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}