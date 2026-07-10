import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';

class TelecallerCallScreen extends StatefulWidget {
  final Map<String, dynamic> account;
  final String accountType; // 'lead' | 'customer'

  const TelecallerCallScreen({
    super.key,
    required this.account,
    required this.accountType,
  });

  @override
  State<TelecallerCallScreen> createState() => _TelecallerCallScreenState();
}

class _TelecallerCallScreenState extends State<TelecallerCallScreen> {
  static const _gold  = Color(0xFFD7BE69);
  static const _bg    = Color(0xFFF5F5F5);
  static const _border    = Color(0xFFEEEEEE);
  static const _green     = Color(0xFF43A047);
  static const _whatsapp  = Color(0xFF25D366);

  final _formKey       = GlobalKey<FormState>();
  final _notesCtrl     = TextEditingController();
  final _rejectCtrl    = TextEditingController();
  final _followUpCtrl  = TextEditingController();

  String? _callOutcome;
  String  _verifyDecision = 'pending'; // 'pending' | 'approve' | 'reject'
  String? _selectedStage;
  String? _selectedFunnelStage;
  bool    _saving = false;
  bool    _called = false; // post-call notes unlock only after the call is placed

  bool get _isLead => widget.accountType == 'lead';

  static const _outcomeOptions = [
    ('answered',   'Answered',        Icons.check_circle_outline_rounded),
    ('busy',       'Busy',            Icons.phone_locked_rounded),
    ('no_answer',  'No Answer',       Icons.phone_missed_rounded),
    ('switch_off', 'Switched Off',    Icons.power_off_rounded),
    ('invalid',    'Invalid Number',  Icons.cancel_outlined),
    ('callback',   'Will Callback',   Icons.schedule_rounded),
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
    // Normalise to the lowercase option keys; drop anything not in the list so
    // the dropdown always has exactly one matching item for its value.
    _selectedStage       = (widget.account['customerStage'] ?? '').toString().toLowerCase().trim();
    _selectedFunnelStage = (widget.account['funnelStage']   ?? '').toString().toLowerCase().trim();
    if (!_stageOptions.contains(_selectedStage))   _selectedStage = null;
    if (!_funnelOptions.contains(_selectedFunnelStage)) _selectedFunnelStage = null;
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _rejectCtrl.dispose();
    _followUpCtrl.dispose();
    super.dispose();
  }

  bool _calling = false;

  Future<void> _call() async {
    final phone = (widget.account['contactNumber'] ?? '').toString();
    if (phone.isEmpty || _calling) return;
    final accountId = (widget.account['id'] ?? '').toString();

    setState(() => _calling = true);
    final result = await ApiService.triggerKnowlarityCall(
      accountId: accountId,
      accountType: widget.accountType,
      customerNumber: phone,
    );
    if (!mounted) return;
    setState(() => _calling = false);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call. Try again.'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _called = true); // unlock the post-call notes
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calling… your phone will ring first, then the customer.')),
    );
  }

  Future<void> _openWhatsApp() async {
    final phone  = (widget.account['contactNumber'] ?? '').toString();
    if (phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final num    = digits.length == 10 ? '91$digits' : digits;
    final uri    = Uri.parse('https://wa.me/$num');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _pickFollowUpDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _gold, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _followUpCtrl.text = formatted);
    }
  }

  Future<void> _submit() async {
    if (!_called) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please place the call first'), backgroundColor: Colors.red),
      );
      return;
    }
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_callOutcome == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a call outcome'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final accountId = (widget.account['id'] ?? '').toString();

      // 1 — Save call log
      await ApiService.createCallLog({
        'account_id':    accountId,
        'account_type':  widget.accountType,
        'call_outcome':  _callOutcome,
        'notes':         _notesCtrl.text.trim(),
        if (_followUpCtrl.text.isNotEmpty) 'follow_up_date': _followUpCtrl.text,
      });

      // 2 — Update lead if applicable
      if (_isLead && accountId.isNotEmpty) {
        final body = <String, dynamic>{};

        if (_selectedStage != null)       body['customerStage'] = _selectedStage;
        if (_selectedFunnelStage != null) body['funnelStage']   = _selectedFunnelStage;

        if (_verifyDecision == 'approve') {
          body['isApproved']        = true;
          body['verificationNotes'] = _notesCtrl.text.trim();
        } else if (_verifyDecision == 'reject') {
          body['isApproved']       = false;
          body['rejectionNotes']   = _rejectCtrl.text.trim();
        }

        if (body.isNotEmpty) {
          await ApiService.updateLeadAccount(accountId, body);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Call logged successfully'),
            backgroundColor: _green,
            duration: Duration(seconds: 2),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name    = (widget.account['businessName']  ?? '').toString();
    final person  = (widget.account['personName']    ?? '').toString();
    final contact = (widget.account['contactNumber'] ?? '').toString();
    final area    = (widget.account['area']          ?? '').toString();
    final city    = (widget.account['city']          ?? '').toString();
    final pincode = (widget.account['pincode']       ?? '').toString();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Call & Verify',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 32),
          children: [

            // ── Contact Header Card ───────────────────────────────────────
            _sectionCard(
              child: Column(
                children: [
                  // Avatar
                  Container(
                    width: 72, height: 72,
                    decoration: const BoxDecoration(
                      color: _gold,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(initial,
                          style: const TextStyle(
                            fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white,
                          )),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Name
                  Text(name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.black87)),

                  if (person.isNotEmpty && person != name) ...[
                    const SizedBox(height: 4),
                    Text(person,
                        style: const TextStyle(fontSize: 13, color: Colors.black45)),
                  ],

                  const SizedBox(height: 8),

                  // Tags
                  Wrap(
                    spacing: 6, runSpacing: 4,
                    alignment: WrapAlignment.center,
                    children: [
                      _isLead
                          ? _tag('Lead', _gold)
                          : _tag('Customer', _green),
                      if (_isLead && (widget.account['customerStage'] ?? '').toString().isNotEmpty)
                        _tag((widget.account['customerStage'] ?? '').toString(), Colors.indigo.shade300),
                      if ((widget.account['userType'] ?? '').toString().isNotEmpty && !_isLead)
                        _tag((widget.account['userType'] ?? '').toString(), Colors.blueGrey),
                    ],
                  ),

                  if (area.isNotEmpty || city.isNotEmpty || pincode.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_on_rounded, size: 13, color: Colors.black38),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            [area, city, pincode].where((s) => s.isNotEmpty).join(' • '),
                            style: const TextStyle(fontSize: 12, color: Colors.black45),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 16),

                  // Call button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: (contact.isNotEmpty && !_calling) ? _call : null,
                      icon: _calling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.call_rounded, size: 20),
                      label: Text(
                        _calling
                            ? 'Calling…'
                            : (contact.isNotEmpty ? 'Call  $contact' : 'No Phone Number'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // WhatsApp button
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _whatsapp,
                        side: const BorderSide(color: _whatsapp),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: contact.isNotEmpty ? _openWhatsApp : null,
                      icon: const FaIcon(FontAwesomeIcons.whatsapp, size: 18),
                      label: const Text('WhatsApp',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Post-Call Dashboard ───────────────────────────────────────
            if (!_called) ...[
              _callFirstBanner(),
              const SizedBox(height: 10),
            ],
            AbsorbPointer(
              absorbing: !_called,
              child: Opacity(
                opacity: _called ? 1 : 0.5,
                child: _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_rounded, color: _gold, size: 20),
                      const SizedBox(width: 8),
                      const Text('Post-Call Notes',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Call Outcome ─────────────────────────────────────────
                  _fieldLabel('Call Outcome *'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    children: _outcomeOptions.map((opt) {
                      final (value, label, icon) = opt;
                      final active = _callOutcome == value;
                      return GestureDetector(
                        onTap: () => setState(() => _callOutcome = value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: active ? _gold : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: active ? _gold : _border),
                            boxShadow: active
                                ? [BoxShadow(color: _gold.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 15,
                                  color: active ? Colors.white : Colors.black45),
                              const SizedBox(width: 6),
                              Text(label,
                                  style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                    color: active ? Colors.white : Colors.black54,
                                  )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // ── Notes ────────────────────────────────────────────────
                  _fieldLabel('Notes'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: _inputDecor(hint: 'What was discussed? Any key observations…'),
                  ),

                  const SizedBox(height: 14),

                  // ── Follow-up Date ───────────────────────────────────────
                  _fieldLabel('Follow-up Date'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _followUpCtrl,
                    readOnly: true,
                    onTap: _pickFollowUpDate,
                    decoration: _inputDecor(
                      hint: 'Select date (optional)',
                      suffix: const Icon(Icons.calendar_today_rounded, size: 18, color: Colors.black38),
                    ),
                  ),

                  // ── Lead-only fields ─────────────────────────────────────
                  if (_isLead) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        const Icon(Icons.tune_rounded, color: _gold, size: 18),
                        const SizedBox(width: 8),
                        const Text('Update Lead Details',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Customer Stage
                    _fieldLabel('Customer Stage'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedStage,
                      decoration: _inputDecor(hint: 'Select stage'),
                      items: _stageOptions.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s[0].toUpperCase() + s.substring(1),
                            style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedStage = v),
                    ),

                    const SizedBox(height: 14),

                    // Funnel Stage
                    _fieldLabel('Funnel Stage'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedFunnelStage,
                      decoration: _inputDecor(hint: 'Select funnel stage'),
                      items: _funnelOptions.map((s) => DropdownMenuItem(
                        value: s,
                        child: Text(s[0].toUpperCase() + s.substring(1),
                            style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedFunnelStage = v),
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),
                    const SizedBox(height: 16),

                    // Verification Decision
                    Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, color: _gold, size: 18),
                        const SizedBox(width: 8),
                        const Text('Verification Decision',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
                      ],
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        _decisionBtn('pending', 'Pending',  Colors.grey,         Icons.hourglass_empty_rounded),
                        const SizedBox(width: 8),
                        _decisionBtn('approve', 'Approve',  _green,               Icons.check_circle_rounded),
                        const SizedBox(width: 8),
                        _decisionBtn('reject',  'Reject',   Colors.red.shade400,  Icons.cancel_rounded),
                      ],
                    ),

                    // Rejection reason (shown only when reject selected)
                    if (_verifyDecision == 'reject') ...[
                      const SizedBox(height: 12),
                      _fieldLabel('Rejection Reason'),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _rejectCtrl,
                        maxLines: 2,
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a rejection reason' : null,
                        decoration: _inputDecor(hint: 'Why is this lead being rejected?'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Submit ────────────────────────────────────────────────────
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: (_saving || !_called) ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : const Text('Save Call Log',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionCard({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
      ],
    ),
    child: child,
  );

  Widget _fieldLabel(String text) => Text(text,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54));

  Widget _callFirstBanner() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: _gold.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _gold.withValues(alpha: 0.5)),
    ),
    child: const Row(
      children: [
        Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFF9C7B1E)),
        SizedBox(width: 8),
        Expanded(
          child: Text('Place the call first to fill the post-call notes',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF9C7B1E))),
        ),
      ],
    ),
  );

  InputDecoration _inputDecor({String hint = '', Widget? suffix}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
    suffixIcon: suffix,
    filled: true,
    fillColor: const Color(0xFFFAFAFA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _gold, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
  );

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withValues(alpha: 0.4)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
  );

  Widget _decisionBtn(String value, String label, Color color, IconData icon) {
    final active = _verifyDecision == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _verifyDecision = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color : _border),
            boxShadow: active
                ? [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))]
                : [],
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: active ? Colors.white : color),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: active ? Colors.white : Colors.black54,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
