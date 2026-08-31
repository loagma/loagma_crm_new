import 'package:flutter/material.dart';

import '../screens/telecaller/telecaller_mock_data.dart' show kGold;

/// The saved-address list to offer for a Create Sales Order delivery —
/// shared by the salesman (Order Funnel) and telecaller (Profile) "take
/// order" flows so both pick a delivery address the exact same way.
///
/// `acc['addresses']` (a list, from BeatPlanController::customerAccountPayload
/// / TelecallerController::worklist) is preferred; a lead account carries no
/// such list, so this falls back to the account's single `address` field —
/// same fallback both flows already relied on before they shared this file.
List<Map<String, dynamic>> addressOptionsFrom(Map<String, dynamic> acc) {
  final raw = (acc['addresses'] as List?) ?? [];
  final list = raw.map((a) => Map<String, dynamic>.from(a as Map)).toList();
  if (list.isEmpty) {
    final addr = ('${acc['address'] ?? ''}').trim();
    if (addr.isNotEmpty) {
      list.add({
        'address': addr,
        'type': null,
        'latitude': acc['latitude'],
        'longitude': acc['longitude'],
      });
    }
  }
  return list;
}

/// Resolves which address a Create Sales Order should ship to: the sole
/// option auto-picked, more than one prompts with [AddressPickerDialog], and
/// none returns null (order sheet just shows no delivery-address section).
/// Returns null (with the dialog never shown) if the user cancels the picker.
Future<Map<String, dynamic>?> resolveDeliveryAddress(
  BuildContext context,
  Map<String, dynamic> acc,
) async {
  final options = addressOptionsFrom(acc);
  if (options.isEmpty) return null;
  if (options.length == 1) return options.first;

  return showDialog<Map<String, dynamic>>(
    context: context,
    builder: (_) => AddressPickerDialog(addresses: options),
  );
}

class AddressPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> addresses;
  const AddressPickerDialog({super.key, required this.addresses});

  @override
  State<AddressPickerDialog> createState() => _AddressPickerDialogState();
}

class _AddressPickerDialogState extends State<AddressPickerDialog> {
  late int _selected;

  @override
  void initState() {
    super.initState();
    final defaultIndex = widget.addresses.indexWhere((a) => a['is_default'] == true);
    _selected = defaultIndex >= 0 ? defaultIndex : 0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Select Delivery Address',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.addresses.length,
          itemBuilder: (_, i) {
            final a = widget.addresses[i];
            final type = ('${a['type'] ?? ''}').trim();
            final label = type.isNotEmpty ? 'Address ${i + 1} ($type)' : 'Address ${i + 1}';
            return RadioListTile<int>(
              value: i,
              groupValue: _selected,
              activeColor: kGold,
              contentPadding: EdgeInsets.zero,
              title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              subtitle: Text('${a['address'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              onChanged: (v) => setState(() => _selected = v ?? 0),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: () => Navigator.pop(context, widget.addresses[_selected]),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
