import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/api_constants.dart';
import '../../core/sync/pocketbase_service.dart';
import '../theme/theme_service.dart';

/// One-time PocketBase credential setup.
///
/// The password used to be shipped inside the APK as a constant in
/// `api_constants.dart`, committed to a public repository. Anything that cloned
/// the repo had full read access to the rider's trips. It is out of source
/// now, which means the app can no longer log in on its own and has to ask.
///
/// This dialog is therefore mandatory on first run, not optional. Parking it
/// behind a settings menu would leave the rider staring at a permanently
/// unsynced Journal with no indication of why.
class SyncSetupDialog extends StatefulWidget {
  final PocketBaseService pbService;

  const SyncSetupDialog({super.key, required this.pbService});

  static Future<bool> show(BuildContext context, PocketBaseService pbService) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SyncSetupDialog(pbService: pbService),
    );
    return result ?? false;
  }

  @override
  State<SyncSetupDialog> createState() => _SyncSetupDialogState();
}

class _SyncSetupDialogState extends State<SyncSetupDialog> {

  /// The active cockpit colour slot. The sheet follows the cockpit rather than
  /// carrying its own palette: a rider who switches to Terik mode for a
  /// daylight fuel stop should not have to switch back to read the receipt.
  ThemeSlot get _slot => ThemeScope.slotOf(context);
  final _emailCtrl = TextEditingController(text: 'zidanesc02@gmail.com');
  final _passCtrl = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Email dan password wajib diisi');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await widget.pbService.setup(email, pass);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : 'Gagal masuk. Cek password dan koneksi.';
    });
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _slot.elevated,
      title: Text(
        'KONEKSI CLOUD',
        style: TextStyle(
          color: _slot.text,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip, servis, dan diagnosa disimpan di server kamu sendiri. '
            'Masukkan akun PocketBase untuk mulai sync.',
            style: TextStyle(color: _slot.dim(0.54), fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.lock_outline, color: _slot.dim(0.3), size: 12),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Disimpan di Android Keystore, tidak ada di source code.',
                  style: TextStyle(
                    color: _slot.dim(0.35),
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _field(_emailCtrl, 'Email', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 10),
          _field(_passCtrl, 'Password', obscure: true),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: _slot.danger, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text('Nanti',
              style: TextStyle(color: _slot.dim(0.54))),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: _slot.accent,
            foregroundColor: _slot.onAccent,
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('HUBUNGKAN'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: _slot.dim(0.54), fontSize: 11)),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: obscure
              ? [FilteringTextInputFormatter.deny(RegExp(r'\s'))]
              : null,
          style: TextStyle(color: _slot.text, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: _slot.dim(0.04),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: _slot.border(0.12)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: _slot.border(0.12)),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the setup prompt when it has never been completed.
Future<void> ensureSyncSetup(BuildContext context, PocketBaseService pbService) async {
  final bootstrapped = await CredentialStore().isBootstrapped();
  if (bootstrapped) return;
  if (!context.mounted) return;
  await SyncSetupDialog.show(context, pbService);
}