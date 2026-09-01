import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import 'telecaller_mock_data.dart' show kComplaintCategories;

class TelecallerCallScreen extends StatefulWidget {
  final Map<String, dynamic> account;
  final String accountType; // 'lead' | 'customer'

  /// When true (opened from the unified worklist-visit screen) the screen is
  /// just the live-call step: once the call finishes it pops back with
  /// {call_log_id, call_outcome, call_status} so the Check Out Action Log
  /// popup can pre-fill, instead of showing its own post-call form.
  final bool returnOnFinish;

  const TelecallerCallScreen({
    super.key,
    required this.account,
    required this.accountType,
    this.returnOnFinish = false,
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

  /// A cloud call was placed and we're still waiting for Knowlarity's
  /// completed-call webhook to resolve its outcome.
  bool get _liveCallInProgress => _liveLogId != null && !_called;

  static const _outcomeOptions = [
    ('answered',   'Answered',        Icons.check_circle_outline_rounded),
    ('busy',       'Busy',            Icons.phone_locked_rounded),
    ('no_answer',  'No Answer',       Icons.phone_missed_rounded),
    ('switch_off', 'Switched Off',    Icons.power_off_rounded),
    ('invalid',    'Invalid Number',  Icons.cancel_outlined),
    ('callback',   'Will Callback',   Icons.schedule_rounded),
    ('complaint',  'Complaint',       Icons.report_problem_rounded),
  ];

  String? _complaintCategory;

  bool get _isComplaint => _callOutcome == 'complaint';

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

    // Landing on this screen already means "place a cloud call" — start it
    // right away instead of making the telecaller tap Call again.
    WidgetsBinding.instance.addPostFrameCallback((_) => _call());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _notesCtrl.dispose();
    _rejectCtrl.dispose();
    _followUpCtrl.dispose();
    super.dispose();
  }

  bool _calling = false;
  Timer? _pollTimer;
  int _pollCount = 0;
  String? _liveLogId;
  Map<String, dynamic>? _liveStatus; // current SR/Knowlarity call-log row, refreshed while the call is live

  // Ticks once per second from the moment the call is placed, since Knowlarity
  // only reports a final outcome+duration once the call has actually ended —
  // there's no live "ringing"/"connected" event to poll. This is what gives
  // the telecaller a running clock while `_liveStatus.outcome` is still 'pending'.
  Timer? _tickTimer;
  int    _elapsedSeconds = 0;

  static const _maxPolls = 40; // ~2 minutes at 3s intervals

  String _fmtDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _call() async {
    final phone = (widget.account['contactNumber'] ?? '').toString();
    if (phone.isEmpty || _calling) return;
    final accountId = (widget.account['id'] ?? '').toString();

    _pollTimer?.cancel();
    _tickTimer?.cancel();
    setState(() {
      _calling = true;
      _called = false;
      _liveLogId = null;
      _liveStatus = null;
      _pollCount = 0;
      _elapsedSeconds = 0;
    });
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

    setState(() => _liveLogId = (result['id'] ?? '').toString());
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Calling… your phone will ring first, then the customer.')),
    );
    if (_liveLogId != null && _liveLogId!.isNotEmpty) {
      _startPolling();
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _called) { timer.cancel(); return; }
        setState(() => _elapsedSeconds++);
      });
    }
  }

  /// Polls the SR/Knowlarity call-log row until the completed-call webhook
  /// flips its outcome away from 'pending', then unlocks the outcome form.
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted || _liveLogId == null) {
        timer.cancel();
        return;
      }
      _pollCount++;
      final status = await ApiService.getCallStatus(_liveLogId!);
      if (!mounted) return;
      if (status != null) setState(() => _liveStatus = status);

      final outcome = (status?['outcome'] ?? '').toString();
      if (outcome.isNotEmpty && outcome != 'pending') {
        timer.cancel();
        _finishLiveCall(outcome);
      } else if (_pollCount >= _maxPolls) {
        // Webhook never landed (not configured yet, or Knowlarity is slow) —
        // stop polling but let the telecaller carry on manually.
        timer.cancel();
      }
    });
  }

  /// Unlocks the post-call notes once the call has actually finished,
  /// pre-filling the outcome Knowlarity detected when it matches one of ours.
  void _finishLiveCall(String detectedOutcome) {
    if (!mounted) return;
    _tickTimer?.cancel();
    if (widget.returnOnFinish) {
      _popWithCall(detectedOutcome);
      return;
    }
    setState(() {
      _called = true;
      if (_outcomeOptions.any((o) => o.$1 == detectedOutcome)) {
        _callOutcome = detectedOutcome;
      }
    });
  }

  /// Manual fallback for when the webhook is delayed or not wired up yet —
  /// lets the telecaller open the outcome form without waiting further.
  void _skipWaitingForWebhook() {
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    if (widget.returnOnFinish) {
      _popWithCall('${_liveStatus?['outcome'] ?? ''}');
      return;
    }
    setState(() => _called = true);
  }

  /// Hand the live call back to the worklist-visit screen so its Check Out
  /// Action Log popup can pre-fill outcome / invalid / status.
  void _popWithCall(String outcome) {
    context.pop(<String, dynamic>{
      'call_log_id': int.tryParse(_liveLogId ?? ''),
      'call_outcome': outcome,
      'is_invalid_call': outcome == 'invalid',
      'call_status': '${_liveStatus?['source'] ?? _liveStatus?['direction'] ?? ''}',
    });
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
    if (_isComplaint && (_complaintCategory == null || _notesCtrl.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category and describe the complaint'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final accountId = (widget.account['id'] ?? '').toString();

      // 1 — Save call log (creates a linked complaint_crm row server-side, in
      // the same transaction, when the outcome is 'complaint')
      await ApiService.createCallLog({
        'account_id':    accountId,
        'account_type':  widget.accountType,
        'call_outcome':  _callOutcome,
        'notes':         _notesCtrl.text.trim(),
        if (_followUpCtrl.text.isNotEmpty) 'follow_up_date': _followUpCtrl.text,
        if (_isComplaint) 'category': _complaintCategory,
        if (_isComplaint) 'description': _notesCtrl.text.trim(),
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
    // Orders don't carry area/city/pincode separately - just one delivery
    // address string - so fall back to that when the structured fields are empty.
    final address = (widget.account['address']       ?? '').toString();
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

                  if (area.isNotEmpty || city.isNotEmpty || pincode.isNotEmpty || address.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.location_on_rounded, size: 13, color: Colors.black38),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            [area, city, pincode].any((s) => s.isNotEmpty)
                                ? [area, city, pincode].where((s) => s.isNotEmpty).join(' • ')
                                : address,
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
                      onPressed: (contact.isNotEmpty && !_calling && !_liveCallInProgress) ? _call : null,
                      icon: _calling
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(_called ? Icons.replay_rounded : Icons.call_rounded, size: 20),
                      label: Text(
                        _calling
                            ? 'Calling…'
                            : _liveCallInProgress
                                ? 'Call in progress…'
                                : _called
                                    ? 'Call Again'
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

            // ── Live SR / Knowlarity call status ────────────────────────────
            if (_liveCallInProgress) ...[
              _liveStatusCard(),
              const SizedBox(height: 10),
            ] else if (_called && _liveStatus != null) ...[
              _callResultCard(),
              const SizedBox(height: 10),
            ] else if (!_called) ...[
              _callFirstBanner(),
              const SizedBox(height: 10),
            ],

            // ── Post-Call Dashboard ───────────────────────────────────────
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

                  // ── Complaint category (only when outcome is Complaint) ───
                  if (_isComplaint) ...[
                    _fieldLabel('Complaint Category *'),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _complaintCategory,
                      isExpanded: true,
                      decoration: _inputDecor(hint: 'Select category'),
                      items: kComplaintCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setState(() => _complaintCategory = v),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Notes ────────────────────────────────────────────────
                  _fieldLabel(_isComplaint ? 'Complaint Description *' : 'Notes'),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: _inputDecor(
                      hint: _isComplaint
                          ? 'What went wrong? Describe the issue…'
                          : 'What was discussed? Any key observations…',
                    ),
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

  /// Live SR / Knowlarity call-log data shown while a cloud call is in
  /// progress — polled every few seconds until the completed-call webhook
  /// resolves the outcome (see [_startPolling]).
  Widget _liveStatusCard() {
    final status = _liveStatus;
    final srNumber = (status?['sr_number'] ?? '').toString();
    final callUuid = (status?['call_uuid'] ?? '').toString();
    final direction = (status?['direction'] ?? '').toString();
    final waitedTooLong = _pollCount >= _maxPolls;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _green),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Call in progress — live SR log',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black87)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _detailRow('Status', waitedTooLong ? 'Still ringing / no update yet' : 'Connecting…'),
          _detailRow('Talk Time', _fmtDuration(_elapsedSeconds)),
          _detailRow('SR Number', srNumber.isNotEmpty ? srNumber : '—'),
          _detailRow('Call UUID', callUuid.isNotEmpty ? callUuid : '—'),
          _detailRow('Direction', direction.isNotEmpty ? direction : '—'),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _skipWaitingForWebhook,
              style: OutlinedButton.styleFrom(foregroundColor: _gold, side: const BorderSide(color: _gold)),
              child: Text(
                  widget.returnOnFinish
                      ? 'Call finished — back to check out'
                      : 'Call already finished — fill outcome now',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  static const _outcomeLabels = {
    'answered':   'Connected',
    'busy':       'Busy',
    'no_answer':  'No Answer',
    'switch_off': 'Switched Off',
    'invalid':    'Invalid Number',
  };

  /// Persistent summary of how the last cloud call actually went, shown once
  /// the outcome has resolved — replaces the live-progress card so the
  /// telecaller can still see the connected status/duration/SR number while
  /// filling out the post-call form below.
  Widget _callResultCard() {
    final status = _liveStatus!;
    final outcome  = (status['outcome'] ?? '').toString();
    final duration = int.tryParse((status['duration_seconds'] ?? 0).toString()) ?? 0;
    final srNumber = (status['sr_number'] ?? '').toString();
    final connected = outcome == 'answered';
    final label = _outcomeLabels[outcome] ?? (outcome.isEmpty ? 'Unknown' : outcome);
    final color = connected ? _green : Colors.orange.shade700;

    return _sectionCard(
      child: Row(
        children: [
          Icon(connected ? Icons.call_end_rounded : Icons.phone_missed_rounded, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                if (srNumber.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('SR $srNumber',
                      style: const TextStyle(fontSize: 11.5, color: Colors.black45)),
                ],
              ],
            ),
          ),
          if (connected)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(_fmtDuration(duration),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _green)),
                const Text('Talk Time',
                    style: TextStyle(fontSize: 10, color: Colors.black45)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12.5, color: Colors.black87))),
      ],
    ),
  );

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
