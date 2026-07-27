import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';

/// Shared approve/reject dialogs for a pending LeadsAccount, used by both
/// PendingLeadsScreen (the review queue) and LeadAccountDetailScreen (full
/// review before deciding). Mirrors the admin_notifications_screen.dart
/// attendance-approval dialog pattern.

const kApprovalRed = Color(0xFFE53935);
const kApprovalGreen = Color(0xFF43A047);

/// Shows a confirm dialog (with an optional notes field), calls the approve
/// API, toasts the result. Returns true if the lead was approved.
Future<bool> confirmApproveLead(BuildContext context, String id, {String businessName = ''}) async {
  final notesCtrl = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Approve Lead', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            businessName.isNotEmpty
                ? 'Approve "$businessName"? This will create a new customer record.'
                : 'Approve this lead? This will create a new customer record.',
            style: const TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notesCtrl,
            decoration: const InputDecoration(
              hintText: 'Verification notes (optional)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kApprovalGreen, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Approve'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final res = await ApiService.approveLeadAccount(id, notes: notesCtrl.text.trim());
  final ok = res != null && res['success'] == true;
  if (context.mounted) {
    Fluttertoast.showToast(
      msg: ok ? 'Lead approved — customer created' : (res?['message']?.toString() ?? 'Failed to approve'),
    );
  }
  return ok;
}

/// Shows a dialog requiring rejection notes, calls the reject API, toasts the
/// result. Returns true if the lead was rejected.
Future<bool> confirmRejectLead(BuildContext context, String id, {String businessName = ''}) async {
  final notesCtrl = TextEditingController();
  final formKey = GlobalKey<FormState>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Reject Lead', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Form(
        key: formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              businessName.isNotEmpty
                  ? 'Tell the creator what needs to be fixed on "$businessName".'
                  : 'Tell the creator what needs to be fixed.',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notesCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Rejection reason (required)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please explain what to fix' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kApprovalRed, foregroundColor: Colors.white),
          onPressed: () {
            if (formKey.currentState?.validate() != true) return;
            Navigator.pop(ctx, true);
          },
          child: const Text('Reject'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final res = await ApiService.rejectLeadAccount(id, notes: notesCtrl.text.trim());
  final ok = res != null && res['success'] == true;
  if (context.mounted) {
    Fluttertoast.showToast(
      msg: ok ? 'Lead rejected' : (res?['message']?.toString() ?? 'Failed to reject'),
    );
  }
  return ok;
}
