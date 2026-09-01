import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/telecaller/telecaller_mock_data.dart'
    show kGold, kGoldDark, kComplaintCategories;

/// The Check Out popup (was the "Order Funnel" tab). Mandatory to complete a
/// check-out; Cancel dismisses it and leaves the user checked in. Role-aware:
///  - salesman  : stage + general notes + "notes related to" + photos +
///                follow-up + payment collected + market note
///  - telecaller : the ex-post-call form (outcome/complaint/notes/follow-up/
///                lead stage) + conversation notes + discussion points, with
///                outcome/invalid/status pre-filled from the call engine.
///
/// Returns the field body for `ApiService.saveActionLog` (timing/GPS/account
/// are added by the caller), or null if cancelled.
Future<Map<String, dynamic>?> showActionLogSheet(
  BuildContext context, {
  required String role, // 'salesman' | 'telecaller'
  required String accountType, // 'lead' | 'customer'
  List<Map<String, dynamic>> stages = const [],
  Map<String, dynamic>? callPrefill,
  List<String> placedOrderIds = const [], // orders placed during this visit
  required Future<String?> Function(List<int> bytes, String name) uploadImage,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    isDismissible: false, // must Cancel or Submit — no accidental dismiss
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => _ActionLogSheet(
      role: role,
      accountType: accountType,
      stages: stages,
      callPrefill: callPrefill,
      placedOrderIds: placedOrderIds,
      uploadImage: uploadImage,
    ),
  );
}

class _ActionLogSheet extends StatefulWidget {
  final String role;
  final String accountType;
  final List<Map<String, dynamic>> stages;
  final Map<String, dynamic>? callPrefill;
  final List<String> placedOrderIds;
  final Future<String?> Function(List<int> bytes, String name) uploadImage;

  const _ActionLogSheet({
    required this.role,
    required this.accountType,
    required this.stages,
    required this.callPrefill,
    required this.placedOrderIds,
    required this.uploadImage,
  });

  @override
  State<_ActionLogSheet> createState() => _ActionLogSheetState();
}

class _ActionLogSheetState extends State<_ActionLogSheet> {
  final _picker = ImagePicker();

  // salesman
  String? _stageSlug;
  final _orderNo = TextEditingController();
  final _generalNotes = TextEditingController();
  String? _notesRelatedTo;
  final _images = <String>[];
  bool _uploading = false;
  final _paymentCollected = TextEditingController();
  String? _paymentMode;
  final _marketNote = TextEditingController();

  // telecaller
  String? _callOutcome;
  bool _isInvalid = false;
  String? _complaintCategory;
  final _conversationNotes = TextEditingController();
  final _discussionPoints = TextEditingController();
  String? _customerStage;
  String? _funnelStage;

  // shared
  DateTime? _followUpDate;
  final _followUpNote = TextEditingController();

  bool get _isSalesman => widget.role == 'salesman';
  bool get _isComplaint => _callOutcome == 'complaint';

  static const _relatedToOptions = [
    'Order', 'Payment', 'Complaint', 'Delivery', 'Product', 'Other',
  ];
  static const _paymentModes = ['Cash', 'UPI', 'Bank', 'Cheque', 'Credit'];
  static const _outcomeOptions = [
    ('answered', 'Answered'),
    ('busy', 'Busy'),
    ('no_answer', 'No Answer'),
    ('switch_off', 'Switched Off'),
    ('invalid', 'Invalid Number'),
    ('callback', 'Will Callback'),
    ('complaint', 'Complaint'),
  ];
  static const _stageOptions = [
    'lead', 'prospect', 'qualified', 'opportunity', 'customer', 'churned',
  ];
  static const _funnelOptions = [
    'awareness', 'interest', 'consideration', 'intent', 'evaluation', 'purchase',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.callPrefill;
    if (p != null) {
      final o = '${p['call_outcome'] ?? p['outcome'] ?? ''}';
      if (_outcomeOptions.any((e) => e.$1 == o)) _callOutcome = o;
      _isInvalid = p['is_invalid_call'] == true || o == 'invalid';
    }
    // Pre-fill the order number with the last order placed during this visit.
    if (widget.placedOrderIds.isNotEmpty) {
      _orderNo.text = widget.placedOrderIds.last;
    }
  }

  @override
  void dispose() {
    _orderNo.dispose();
    _generalNotes.dispose();
    _paymentCollected.dispose();
    _marketNote.dispose();
    _conversationNotes.dispose();
    _discussionPoints.dispose();
    _followUpNote.dispose();
    super.dispose();
  }

  Future<void> _addImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 80);
    } catch (_) {}
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    final bytes = await picked.readAsBytes();
    final name = picked.name.isNotEmpty ? picked.name : 'action.jpg';
    final path = await widget.uploadImage(bytes, name);
    if (!mounted) return;
    setState(() {
      _uploading = false;
      if (path != null && path.isNotEmpty) _images.add(path);
    });
  }

  Future<void> _pickFollowUp() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _followUpDate ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: kGold, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _followUpDate = picked);
  }

  bool get _isPlacedOrder => _stageSlug == 'placed_order';

  void _submit() {
    if (_isSalesman && _stageSlug == null) {
      _err('Pick a stage before checking out');
      return;
    }
    if (_isSalesman && _isPlacedOrder && _orderNo.text.trim().isEmpty) {
      _err('Enter the order number for the placed order');
      return;
    }
    if (!_isSalesman && _callOutcome == null) {
      _err('Pick a call outcome before checking out');
      return;
    }
    if (!_isSalesman && _isComplaint &&
        (_complaintCategory == null || _conversationNotes.text.trim().isEmpty)) {
      _err('Pick a complaint category and describe it');
      return;
    }

    final body = <String, dynamic>{};
    final fu = _followUpDate;
    if (fu != null) {
      body['follow_up_date'] =
          '${fu.year}-${fu.month.toString().padLeft(2, '0')}-${fu.day.toString().padLeft(2, '0')}';
      if (_followUpNote.text.trim().isNotEmpty) body['follow_up_note'] = _followUpNote.text.trim();
    }

    if (_isSalesman) {
      body['outcome_slug'] = _stageSlug;
      if (_isPlacedOrder) body['order_no'] = _orderNo.text.trim();
      if (_generalNotes.text.trim().isNotEmpty) body['general_notes'] = _generalNotes.text.trim();
      if (_notesRelatedTo != null) body['notes_related_to'] = _notesRelatedTo;
      if (_images.isNotEmpty) body['images'] = List<String>.from(_images);
      final pay = double.tryParse(_paymentCollected.text.trim());
      if (pay != null && pay > 0) {
        body['payment_collected'] = pay;
        if (_paymentMode != null) body['payment_mode'] = _paymentMode;
      }
      if (_marketNote.text.trim().isNotEmpty) body['market_note'] = _marketNote.text.trim();
    } else {
      body['call_outcome'] = _callOutcome;
      body['is_invalid_call'] = _isInvalid || _callOutcome == 'invalid';
      final p = widget.callPrefill;
      if (p != null) {
        if (p['call_status'] != null) body['call_status'] = '${p['call_status']}';
        final clid = p['call_log_id'] ?? p['id'];
        if (clid != null) body['call_log_id'] = int.tryParse('$clid');
      }
      if (_conversationNotes.text.trim().isNotEmpty) {
        body['conversation_notes'] = _conversationNotes.text.trim();
      }
      if (_discussionPoints.text.trim().isNotEmpty) {
        body['discussion_points'] = _discussionPoints.text.trim();
      }
      if (_generalNotes.text.trim().isNotEmpty) body['general_notes'] = _generalNotes.text.trim();
      if (widget.accountType == 'lead') {
        if (_customerStage != null) body['customer_stage'] = _customerStage;
        if (_funnelStage != null) body['funnel_stage'] = _funnelStage;
      }
      if (_isComplaint) {
        body['category'] = _complaintCategory;
        body['description'] = _conversationNotes.text.trim();
      }
    }

    Navigator.pop(context, body);
  }

  void _err(String m) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(m), backgroundColor: Colors.red),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 10, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(top: 4, bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.assignment_turned_in_rounded, color: kGold, size: 20),
                const SizedBox(width: 8),
                const Text('Action Log', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                Text(_isSalesman ? 'Visit' : 'Call',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 4),
            Text('Fill this to complete check-out.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 14),

            if (_isSalesman) ..._salesmanForm() else ..._telecallerForm(),

            const SizedBox(height: 12),
            _label('Follow-up / next visit (optional)'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _pickFollowUp,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: _boxDeco(),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _followUpDate == null
                                  ? 'Select date'
                                  : '${_followUpDate!.day}/${_followUpDate!.month}/${_followUpDate!.year}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const Icon(Icons.calendar_today_rounded, size: 15, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_followUpDate != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () => setState(() => _followUpDate = null),
                  ),
              ],
            ),
            if (_followUpDate != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _followUpNote,
                decoration: _inputDecor('What is the next step?'),
              ),
            ],

            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.grey.shade700,
                      side: BorderSide(color: Colors.grey.shade300),
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Save & Check Out', style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Salesman ──────────────────────────────────────────────────────────────
  List<Widget> _salesmanForm() {
    return [
      _label('Stage *'),
      const SizedBox(height: 6),
      if (widget.stages.isEmpty)
        Text('No stages configured.', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500))
      else
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: widget.stages.map((s) {
            final slug = '${s['slug']}';
            final active = _stageSlug == slug;
            return GestureDetector(
              onTap: () => setState(() => _stageSlug = slug),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? kGold.withValues(alpha: 0.16) : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: active ? kGold : const Color(0xFFE0E0E0), width: 1.4),
                ),
                child: Text('${s['name']}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? kGoldDark : Colors.black87)),
              ),
            );
          }).toList(),
        ),
      if (_isPlacedOrder) ...[
        const SizedBox(height: 14),
        _label('Order number *'),
        const SizedBox(height: 6),
        TextField(
          controller: _orderNo,
          keyboardType: TextInputType.text,
          decoration: _inputDecor(widget.placedOrderIds.isNotEmpty
              ? 'Order placed this visit'
              : 'Enter the placed order number'),
        ),
        if (widget.placedOrderIds.length > 1) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.placedOrderIds
                .map((id) => GestureDetector(
                      onTap: () => setState(() => _orderNo.text = id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _orderNo.text == id ? kGold.withValues(alpha: 0.16) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _orderNo.text == id ? kGold : const Color(0xFFE0E0E0)),
                        ),
                        child: Text('#$id', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ))
                .toList(),
          ),
        ],
      ],
      const SizedBox(height: 14),
      _label('General notes'),
      const SizedBox(height: 6),
      TextField(controller: _generalNotes, maxLines: 3, decoration: _inputDecor('Enter general notes…')),
      const SizedBox(height: 14),
      _label('Notes related to'),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _notesRelatedTo,
        isExpanded: true,
        decoration: _inputDecor('Select'),
        items: _relatedToOptions
            .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13))))
            .toList(),
        onChanged: (v) => setState(() => _notesRelatedTo = v),
      ),
      const SizedBox(height: 14),
      _label('Photos'),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          ..._images.asMap().entries.map((e) => Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_rounded, color: Colors.black26),
                  ),
                  Positioned(
                    right: -8,
                    top: -8,
                    child: IconButton(
                      icon: const Icon(Icons.cancel, size: 18, color: Colors.redAccent),
                      onPressed: () => setState(() => _images.removeAt(e.key)),
                    ),
                  ),
                ],
              )),
          GestureDetector(
            onTap: (_uploading) ? null : _addImage,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kGold),
              ),
              child: _uploading
                  ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : const Icon(Icons.add_a_photo_rounded, color: kGold),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _label('Payment collected (optional)'),
      const SizedBox(height: 6),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _paymentCollected,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: _inputDecor('₹ amount'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _paymentMode,
              isExpanded: true,
              decoration: _inputDecor('Mode'),
              items: _paymentModes
                  .map((o) => DropdownMenuItem(value: o, child: Text(o, style: const TextStyle(fontSize: 13))))
                  .toList(),
              onChanged: (v) => setState(() => _paymentMode = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _label('Market / competitor note (optional)'),
      const SizedBox(height: 6),
      TextField(controller: _marketNote, maxLines: 2, decoration: _inputDecor('Competitor stock, pricing, shelf…')),
    ];
  }

  // ── Telecaller ────────────────────────────────────────────────────────────
  List<Widget> _telecallerForm() {
    return [
      _label('Call outcome *'),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _outcomeOptions.map((o) {
          final active = _callOutcome == o.$1;
          return GestureDetector(
            onTap: () => setState(() => _callOutcome = o.$1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: active ? kGold.withValues(alpha: 0.16) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: active ? kGold : const Color(0xFFE0E0E0), width: 1.4),
              ),
              child: Text(o.$2,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? kGoldDark : Colors.black87)),
            ),
          );
        }).toList(),
      ),
      const SizedBox(height: 10),
      CheckboxListTile(
        value: _isInvalid,
        onChanged: (v) => setState(() => _isInvalid = v ?? false),
        title: const Text('Invalid call', style: TextStyle(fontSize: 13)),
        contentPadding: EdgeInsets.zero,
        dense: true,
        controlAffinity: ListTileControlAffinity.leading,
        activeColor: kGold,
      ),
      if (widget.callPrefill?['call_status'] != null) ...[
        const SizedBox(height: 2),
        Text('Engine status: ${widget.callPrefill!['call_status']}',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
      ],
      if (_isComplaint) ...[
        const SizedBox(height: 12),
        _label('Complaint category *'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _complaintCategory,
          isExpanded: true,
          decoration: _inputDecor('Select category'),
          items: kComplaintCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
              .toList(),
          onChanged: (v) => setState(() => _complaintCategory = v),
        ),
      ],
      const SizedBox(height: 14),
      _label(_isComplaint ? 'Complaint description *' : 'Conversation notes'),
      const SizedBox(height: 6),
      TextField(controller: _conversationNotes, maxLines: 3, decoration: _inputDecor('What was discussed…')),
      const SizedBox(height: 14),
      _label('Call log / discussion points'),
      const SizedBox(height: 6),
      TextField(controller: _discussionPoints, maxLines: 3, decoration: _inputDecor('Pitch given, objections, next step…')),
      if (widget.accountType == 'lead') ...[
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Customer stage'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _customerStage,
                    isExpanded: true,
                    decoration: _inputDecor('Stage'),
                    items: _stageOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(_cap(s), style: const TextStyle(fontSize: 12.5))))
                        .toList(),
                    onChanged: (v) => setState(() => _customerStage = v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _label('Funnel stage'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _funnelStage,
                    isExpanded: true,
                    decoration: _inputDecor('Funnel'),
                    items: _funnelOptions
                        .map((s) => DropdownMenuItem(value: s, child: Text(_cap(s), style: const TextStyle(fontSize: 12.5))))
                        .toList(),
                    onChanged: (v) => setState(() => _funnelStage = v),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    ];
  }

  // ── shared bits ──────────────────────────────────────────────────────────
  String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Widget _label(String t) => Text(t,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87));

  BoxDecoration _boxDeco() => BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      );

  InputDecoration _inputDecor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.all(12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kGold)),
      );
}
