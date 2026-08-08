import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/account_map_screen.dart';
import '../telecaller/telecaller_actions.dart';

/// Complaint ticket list. Role-aware: salesman/telecaller default to tickets
/// they raised (own status tracking); admin/incharge-type roles default to a
/// hierarchy-scoped queue (mirrors AttendanceController's approval scoping).
/// Everyone — any role — can also switch to an "Assigned to Me" view, since a
/// complaint can be delegated all the way down to a salesman/telecaller, not
/// just to fellow incharges. Whoever a ticket is currently assigned to gets
/// a status-update action on it even outside their normal scope; only
/// incharge-type roles (and admin) can re-delegate it further.
class ComplaintsScreen extends StatefulWidget {
  final bool initialAssignedToMe;

  const ComplaintsScreen({super.key, this.initialAssignedToMe = false});

  @override
  State<ComplaintsScreen> createState() => _ComplaintsScreenState();
}

class _ComplaintsScreenState extends State<ComplaintsScreen> {
  static const _gold = Color(0xFFD7BE69);

  List<Map<String, dynamic>> _records = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  String _statusFilter = 'all'; // all | open | in_progress | resolved | closed
  late bool _assignedToMe = widget.initialAssignedToMe;
  final _scroll = ScrollController();

  bool get _isApprover {
    final role = (UserService.currentRole ?? '').toLowerCase().trim();
    return role != 'salesman' && role != 'telecaller';
  }

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100 && !_loading && _hasMore) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading && !refresh) return;
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _records = [];
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.getComplaints(
        page: _page,
        assignedTo: _assignedToMe ? UserService.currentMobile : null,
        // Non-approvers (salesman/telecaller) default to their own raised
        // tickets; ignored when the "Assigned to Me" scope is active.
        raisedBy: (_assignedToMe || _isApprover) ? null : UserService.currentMobile,
        status: _statusFilter == 'all' ? null : _statusFilter,
      );
      if (!mounted) return;
      final items = (res['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final meta = res['meta'] as Map?;
      setState(() {
        _records.addAll(items);
        _hasMore = _page < (meta?['last_page'] as int? ?? 1);
        _page++;
      });
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setStatusFilter(String status) {
    if (_statusFilter == status) return;
    setState(() => _statusFilter = status);
    _load(refresh: true);
  }

  void _setAssignedToMe(bool value) {
    if (_assignedToMe == value) return;
    setState(() => _assignedToMe = value);
    _load(refresh: true);
  }

  Future<void> _updateStatus(Map<String, dynamic> record, int index) async {
    String status = record['status']?.toString() ?? 'open';
    final notesCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Update Status', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                value: status,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(value: 'in_progress', child: Text('In Progress')),
                  DropdownMenuItem(value: 'resolved', child: Text('Resolved')),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: (v) => setDialogState(() => status = v ?? status),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(
                  hintText: 'Resolution notes (optional)',
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
              style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await ApiService.updateComplaintStatus(
      record['id'] as int,
      status: status,
      resolutionNotes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _records[index] = {...record, 'status': status, 'resolution_notes': notesCtrl.text.trim()};
      });
      Fluttertoast.showToast(msg: 'Status updated');
    } else {
      Fluttertoast.showToast(msg: 'Failed to update status');
    }
  }

  /// Staff this user may hand a complaint to: themself, plus everyone in
  /// their own downward incharge hierarchy (admin may assign to anyone).
  /// Mirrors the recursive walk in MyInchargesScreen / getDescendantMobiles.
  Future<List<Map<String, String>>> _loadAssignableStaff() async {
    final role = (UserService.currentRole ?? '').toLowerCase().trim();
    final selfMobile = (UserService.currentMobile ?? '').trim();

    final results = await Future.wait([
      ApiService.getAllInchargeAssigns(),
      ApiService.getEmployees(perPage: 500),
    ]);
    final allAssigns = results[0];
    final allStaff = results[1];

    final empByMobile = <String, Map<String, dynamic>>{
      for (final e in allStaff) (e['mobile'] ?? '').toString().trim(): e,
    };

    final Set<String> targets;
    if (role == 'admin') {
      targets = empByMobile.keys.where((m) => m.isNotEmpty && m != selfMobile).toSet();
    } else {
      final childIdsOf = <String, List<String>>{};
      for (final a in allAssigns) {
        final parentId = (a['head_incharge_id'] ?? '').toString();
        final ids = a['incharge_ids'];
        if (parentId.isEmpty || parentId == '0' || ids is! List) continue;
        childIdsOf[parentId] =
            ids.map((e) => e.toString()).where((s) => s.isNotEmpty && s != '0').toList();
      }
      targets = <String>{};
      final stack = [selfMobile];
      final visited = {selfMobile};
      while (stack.isNotEmpty) {
        final cur = stack.removeLast();
        for (final child in childIdsOf[cur] ?? const <String>[]) {
          if (visited.contains(child)) continue;
          visited.add(child);
          targets.add(child);
          stack.add(child);
        }
      }
    }

    final list = targets
        .where((m) => empByMobile.containsKey(m)) // drop stale/removed staff
        .map((m) => {
              'mobile': m,
              'name': (empByMobile[m]?['name'] ?? '').toString(),
              'role': (empByMobile[m]?['role'] ?? '').toString(),
            })
        .toList();
    list.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    return list;
  }

  Future<void> _assignComplaint(Map<String, dynamic> record, int index) async {
    final selfMobile = (UserService.currentMobile ?? '').trim();
    final selfName = (UserService.currentName ?? '').trim();
    final selfRole = (UserService.currentRole ?? '').trim();

    List<Map<String, String>> staff;
    try {
      staff = await _loadAssignableStaff();
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Failed to load team: $e');
      return;
    }
    if (!mounted) return;

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => _AssignDialog(
        staff: staff,
        selfMobile: selfMobile,
        selfName: selfName.isEmpty ? 'Myself' : selfName,
        selfRole: selfRole,
        currentAssignee: record['assigned_to']?.toString(),
      ),
    );
    if (selected == null || !mounted) return;

    final res = await ApiService.assignComplaint(record['id'] as int, assignedTo: selected);
    if (!mounted) return;

    if (res != null && !res.containsKey('errors')) {
      final data = Map<String, dynamic>.from(res['data'] as Map? ?? {});
      setState(() {
        _records[index] = {..._records[index], ...data};
      });
      Fluttertoast.showToast(msg: 'Complaint assigned');
    } else {
      Fluttertoast.showToast(msg: res?['errors']?.toString() ?? 'Failed to assign complaint');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _assignedToMe ? 'Assigned to Me' : (_isApprover ? 'Complaints' : 'My Complaints');
    final myMobile = UserService.currentMobile ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => _load(refresh: true))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _scopeChip(false, _isApprover ? 'All' : 'Raised by Me'),
                  const SizedBox(width: 6),
                  _scopeChip(true, 'Assigned to Me'),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip('all', 'All'),
                  const SizedBox(width: 6),
                  _filterChip('open', 'Open'),
                  const SizedBox(width: 6),
                  _filterChip('in_progress', 'In Progress'),
                  const SizedBox(width: 6),
                  _filterChip('resolved', 'Resolved'),
                  const SizedBox(width: 6),
                  _filterChip('closed', 'Closed'),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading && _records.isEmpty
                ? const Center(child: CircularProgressIndicator(color: _gold))
                : !_loading && _records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF43A047)),
                            const SizedBox(height: 12),
                            Text(
                              _statusFilter == 'all' ? 'No complaints' : 'No complaints match this filter',
                              style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: _gold,
                        onRefresh: () => _load(refresh: true),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(14),
                          itemCount: _records.length + (_loading || _hasMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _records.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(color: _gold)),
                              );
                            }
                            final record = _records[i];
                            final assignedToMobile = (record['assigned_to'] ?? '').toString();
                            // Whoever it's assigned to may act on it even if they're a
                            // leaf role (salesman/telecaller) outside the normal approver
                            // set; only incharge-type roles/admin may re-delegate further.
                            final canUpdateStatus = _isApprover ||
                                (assignedToMobile.isNotEmpty && assignedToMobile == myMobile);
                            return _ComplaintCard(
                              record: record,
                              showRaisedBy: canUpdateStatus,
                              canAssign: _isApprover,
                              onUpdateStatus: () => _updateStatus(_records[i], i),
                              onAssign: () => _assignComplaint(_records[i], i),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _scopeChip(bool value, String label) {
    final selected = _assignedToMe == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setAssignedToMe(value),
      selectedColor: const Color(0xFF1565C0).withValues(alpha: 0.15),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: selected ? const Color(0xFF1565C0) : Colors.black87,
      ),
      side: BorderSide(color: selected ? const Color(0xFF1565C0) : Colors.grey.shade300),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setStatusFilter(value),
      selectedColor: _gold.withValues(alpha: 0.25),
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: selected ? const Color(0xFFC09E3E) : Colors.black87,
      ),
      side: BorderSide(color: selected ? _gold : Colors.grey.shade300),
    );
  }
}

class _ComplaintCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool showRaisedBy;
  final bool canAssign;
  final VoidCallback onUpdateStatus;
  final VoidCallback onAssign;

  const _ComplaintCard({
    required this.record,
    required this.showRaisedBy,
    required this.canAssign,
    required this.onUpdateStatus,
    required this.onAssign,
  });

  static const _statusColors = <String, Color>{
    'open': Color(0xFFF59E0B),
    'in_progress': Color(0xFF1E88E5),
    'resolved': Color(0xFF43A047),
    'closed': Color(0xFF757575),
  };

  static const _statusLabels = <String, String>{
    'open': 'Open',
    'in_progress': 'In Progress',
    'resolved': 'Resolved',
    'closed': 'Closed',
  };

  String _relative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Widget _iconBtn(IconData? icon, Color color, VoidCallback? onTap, {String? tooltip, IconData? faIcon}) {
    final iconColor = onTap != null ? color : color.withValues(alpha: 0.35);
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: color.withValues(alpha: onTap != null ? 0.12 : 0.05), shape: BoxShape.circle),
        child: Center(
          child: faIcon != null ? FaIcon(faIcon, size: 14, color: iconColor) : Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  /// Small "icon + bold label + value" row — used for Owner/Address/Resolution
  /// so the meaning of each line is explicit, not left to infer from an icon.
  Widget _labeledLine(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Text('$label: ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(value, style: const TextStyle(fontSize: 11.5, color: Colors.black87), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = record['status']?.toString() ?? 'open';
    final color = _statusColors[status] ?? Colors.grey;
    final accountName = record['account_name']?.toString() ?? 'Unknown account';
    final accountOwner = record['account_owner']?.toString() ?? '';
    final accountPhone = record['account_phone']?.toString() ?? '';
    final accountAddress = record['account_address']?.toString() ?? '';
    final accountArea = record['account_area']?.toString() ?? '';
    final accountCity = record['account_city']?.toString() ?? '';
    final accountLat = _toDouble(record['account_latitude']);
    final accountLng = _toDouble(record['account_longitude']);
    final accountType = record['account_type']?.toString() ?? 'lead';
    final category = record['category']?.toString() ?? '';
    final description = record['description']?.toString() ?? '';
    final source = record['source_channel']?.toString() ?? '';
    final raisedByMobile = record['raised_by']?.toString() ?? '';
    final raisedByName = record['raised_by_name']?.toString();
    final raisedByRole = record['raised_by_role']?.toString() ?? '';
    final raisedByLabel = (raisedByName != null && raisedByName.isNotEmpty) ? raisedByName : raisedByMobile;
    final assignedToMobile = record['assigned_to']?.toString() ?? '';
    final assignedToName = record['assigned_to_name']?.toString() ?? '';
    final assignedToRole = record['assigned_to_role']?.toString() ?? '';
    final assignedToLabel = assignedToName.isNotEmpty ? assignedToName : assignedToMobile;
    final resolutionNotes = record['resolution_notes']?.toString() ?? '';
    final location = [accountArea, accountCity].where((s) => s.isNotEmpty).join(', ');

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account block ─────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(accountName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                  child: Text(_statusLabels[status] ?? status,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
                ),
              ],
            ),
            if (accountOwner.isNotEmpty) ...[
              const SizedBox(height: 3),
              _labeledLine(Icons.person_outline_rounded, 'Owner', accountOwner),
            ],
            if (accountAddress.isNotEmpty || location.isNotEmpty) ...[
              const SizedBox(height: 3),
              _labeledLine(
                Icons.location_on_outlined,
                'Address',
                [accountAddress, location].where((s) => s.isNotEmpty).join(' · '),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    accountPhone.isNotEmpty ? accountPhone : 'No phone on file',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.black87),
                  ),
                ),
                _iconBtn(Icons.call_rounded, const Color(0xFF43A047),
                    accountPhone.isNotEmpty ? () => launchPhoneCall(accountPhone) : null,
                    tooltip: 'Call account'),
                const SizedBox(width: 6),
                _iconBtn(null, const Color(0xFF25D366), accountPhone.isNotEmpty ? () => launchWhatsApp(accountPhone) : null,
                    tooltip: 'WhatsApp account',
                    faIcon: FontAwesomeIcons.whatsapp),
                const SizedBox(width: 6),
                _iconBtn(
                  Icons.map_rounded,
                  const Color(0xFF1565C0),
                  (accountLat != null && accountLng != null)
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AccountMapScreen(
                                title: accountName,
                                accounts: [
                                  {
                                    'businessName': accountName,
                                    'latitude': accountLat,
                                    'longitude': accountLng,
                                    '_type': accountType,
                                  }
                                ],
                              ),
                            ),
                          )
                      : null,
                  tooltip: 'Show on map',
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Complaint details ────────────────────────────────────────
            if (category.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                child: Text(category, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black87)),
              ),
            Text(description, style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
            if (resolutionNotes.isNotEmpty) ...[
              const SizedBox(height: 6),
              _labeledLine(Icons.notes_rounded, 'Resolution', resolutionNotes),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Raised-by / source ───────────────────────────────────────
            Row(
              children: [
                Icon(
                  source == 'telecaller_call' ? Icons.call_rounded : Icons.storefront_rounded,
                  size: 13,
                  color: Colors.black45,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    source == 'telecaller_call' ? 'Raised during a telecaller call' : 'Raised during a salesman visit',
                    style: const TextStyle(fontSize: 11, color: Colors.black45),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(_relative(record['created_at']?.toString()), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              ],
            ),
            if (showRaisedBy && raisedByLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.support_agent_rounded, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'By $raisedByLabel'
                      '${raisedByRole.isNotEmpty ? ' ($raisedByRole)' : ''}'
                      '${raisedByMobile.isNotEmpty ? ' · $raisedByMobile' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.black54, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (raisedByMobile.isNotEmpty)
                    _iconBtn(Icons.call_rounded, const Color(0xFF8E24AA), () => launchPhoneCall(raisedByMobile),
                        tooltip: 'Call $raisedByLabel'),
                ],
              ),
            ],
            if (showRaisedBy) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    assignedToLabel.isNotEmpty ? Icons.assignment_ind_rounded : Icons.assignment_late_outlined,
                    size: 13,
                    color: assignedToLabel.isNotEmpty ? const Color(0xFF1565C0) : Colors.grey.shade400,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      assignedToLabel.isNotEmpty
                          ? 'Assigned to $assignedToLabel${assignedToRole.isNotEmpty ? ' ($assignedToRole)' : ''}'
                          : 'Not yet assigned',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: assignedToLabel.isNotEmpty ? const Color(0xFF1565C0) : Colors.grey.shade500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onUpdateStatus,
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      label: const Text('Update Status', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  if (canAssign) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onAssign,
                        style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF1565C0)),
                        icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                        label: Text(assignedToLabel.isNotEmpty ? 'Reassign' : 'Assign',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Picker for who a complaint should be handed to: the current user
/// ("solve it myself") pinned at the top, plus everyone in their own
/// downward hierarchy (or, for admin, every staff member). Returns the
/// chosen mobile via [Navigator.pop], or null if cancelled.
class _AssignDialog extends StatefulWidget {
  final List<Map<String, String>> staff;
  final String selfMobile;
  final String selfName;
  final String selfRole;
  final String? currentAssignee;

  const _AssignDialog({
    required this.staff,
    required this.selfMobile,
    required this.selfName,
    required this.selfRole,
    required this.currentAssignee,
  });

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  static const _gold = Color(0xFFD7BE69);
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.staff
        : widget.staff
            .where((s) =>
                (s['name'] ?? '').toLowerCase().contains(q) || (s['mobile'] ?? '').contains(q))
            .toList();
    final selfMatches = q.isEmpty ||
        widget.selfName.toLowerCase().contains(q) ||
        widget.selfMobile.contains(q);

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
      title: Row(
        children: [
          const Expanded(
            child: Text('Assign Complaint',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.black87)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.close_rounded, color: Colors.grey.shade600),
            tooltip: 'Close',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: Colors.black87, fontSize: 13.5),
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search team by name or mobile…',
                hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.grey.shade600),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _gold, width: 1.5)),
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (selfMatches)
                    _tile(
                      mobile: widget.selfMobile,
                      name: '${widget.selfName} (Myself)',
                      role: widget.selfRole,
                      icon: Icons.person_pin_circle_rounded,
                    ),
                  ...filtered.map((s) => _tile(
                        mobile: s['mobile'] ?? '',
                        name: s['name'] ?? '',
                        role: s['role'] ?? '',
                        icon: Icons.person_rounded,
                      )),
                  if (!selfMatches && filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No matches', style: TextStyle(color: Colors.grey.shade600)),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  Widget _tile({required String mobile, required String name, required String role, required IconData icon}) {
    final isCurrent = widget.currentAssignee != null && widget.currentAssignee == mobile;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: _gold.withValues(alpha: 0.15),
        child: Icon(icon, size: 16, color: _gold),
      ),
      title: Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Colors.black87)),
      subtitle: Text(
        [if (role.isNotEmpty) role, mobile].where((s) => s.isNotEmpty).join(' · '),
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
      ),
      trailing: isCurrent ? const Icon(Icons.check_circle_rounded, color: Color(0xFF43A047), size: 20) : null,
      onTap: () => Navigator.pop(context, mobile),
    );
  }
}
