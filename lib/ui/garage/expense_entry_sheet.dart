import 'package:flutter/material.dart';

import '../../core/garage/expense_ledger.dart';
import '../../core/trip/trip_manager.dart';
import '../theme/theme_service.dart';

/// Records a non-fuel running cost: a service, a tyre, insurance, a road tax.
///
/// Kept separate from the fuel log because fuel has full-to-full accounting
/// and every other cost does not. Asking one sheet to do both means the fuel
/// fields are mostly empty here, which makes it slower to use.
class ExpenseEntrySheet extends StatefulWidget {
  final double currentOdometer;

  const ExpenseEntrySheet({
    super.key,
    required this.currentOdometer,
  });

  static Future<void> show(
    BuildContext context, {
    required double currentOdometer,
  }) {
    return showModalBottomSheet(
      context: context,
      // Read from the caller's context, not from an instance: a static has no
      // `this`.
      backgroundColor: ThemeScope.slotOf(context).elevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ExpenseEntrySheet(currentOdometer: currentOdometer),
      ),
    );
  }

  @override
  State<ExpenseEntrySheet> createState() => _ExpenseEntrySheetState();
}

class _ExpenseEntrySheetState extends State<ExpenseEntrySheet> {

  /// The active cockpit colour slot. The sheet follows the cockpit rather than
  /// carrying its own palette: a rider who switches to Terik mode for a
  /// daylight fuel stop should not have to switch back to read the receipt.
  ThemeSlot get _slot => ThemeScope.slotOf(context);
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  /// Initialised in initState: a field initialiser cannot read `widget`.
  late final TextEditingController _odoCtrl;

  ExpenseCategory _category = ExpenseCategory.service;
  String? _error;

  @override
  void initState() {
    super.initState();
    _odoCtrl =
        TextEditingController(text: widget.currentOdometer.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    _odoCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final odo = double.tryParse(_odoCtrl.text.trim());

    if (amount == null || amount <= 0) {
      setState(() => _error = 'Masukkan nominal yang valid');
      return;
    }
    if (odo == null || odo <= 0) {
      setState(() => _error = 'Masukkan kilometers yang valid');
      return;
    }

    ExpenseLedger().add(
      category: _category,
      amountIdr: amount,
      odometerKm: odo,
      note: _noteCtrl.text.trim(),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CATAT PENGELUARAN',
            style: TextStyle(
              color: _slot.text,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in ExpenseCategory.values)
                if (c != ExpenseCategory.fuel)
                  GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _category == c
                            ? Color(c.colorValue).withOpacity(0.22)
                            : _slot.dim(0.04),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _category == c
                              ? Color(c.colorValue)
                              : _slot.border(0.12),
                        ),
                      ),
                      child: Text(
                        c.label,
                        style: TextStyle(
                          color: _category == c
                              ? Color(c.colorValue)
                              : _slot.dim(0.54),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
          const SizedBox(height: 14),

          _field(_amountCtrl, 'Nominal (Rp)', '250000',
              keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          _field(_odoCtrl, 'Odometer (km)',
              widget.currentOdometer.toStringAsFixed(0),
              keyboardType: TextInputType.number),
          const SizedBox(height: 10),
          _field(_noteCtrl, 'Catatan (opsional)', 'Bengkel, parts...'),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: TextStyle(color: _slot.danger, fontSize: 12)),
          ],

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _slot.accent,
                foregroundColor: _slot.onAccent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('SIMPAN',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(color: _slot.dim(0.54), fontSize: 11)),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          keyboardType: keyboardType,
          style: TextStyle(color: _slot.text, fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _slot.border(0.24)),
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