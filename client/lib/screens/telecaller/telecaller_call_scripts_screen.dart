import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import 'telecaller_mock_data.dart';

/// Call Scripts (live, telecaller-managed). Each telecaller has their own list
/// of talking points and can Add / Edit / Delete them. Defaults are seeded by
/// the backend the first time the screen is opened.
class TelecallerCallScriptsScreen extends StatefulWidget {
  const TelecallerCallScriptsScreen({super.key});

  @override
  State<TelecallerCallScriptsScreen> createState() => _TelecallerCallScriptsScreenState();
}

class _TelecallerCallScriptsScreenState extends State<TelecallerCallScriptsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _scripts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final scripts = await ApiService.getCallScripts();
    if (!mounted) return;
    setState(() {
      _scripts = scripts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Call Scripts'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: kGoldDark,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Script'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _scripts.isEmpty
              ? _emptyView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 90),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: kGold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kGold.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book_rounded, color: kGoldDark, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text('Tap a stage to expand. Use the menu to edit or delete.',
                                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
                            ),
                          ],
                        ),
                      ),
                      ..._scripts.map((s) => _ScriptCard(
                            script: s,
                            onEdit: () => _openEditor(existing: s),
                            onDelete: () => _delete(s),
                          )),
                    ],
                  ),
                ),
    );
  }

  Widget _emptyView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text('No scripts yet', style: TextStyle(fontSize: 16, color: Colors.grey.shade500)),
          const SizedBox(height: 4),
          Text('Tap “Add Script” to create one', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
        ],
      ),
    );
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final id = s['id'] as int?;
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete script?'),
        content: Text('“${s['title']}” will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    final ok = await ApiService.deleteCallScript(id);
    if (!mounted) return;
    if (ok) {
      Fluttertoast.showToast(msg: 'Deleted', backgroundColor: kGoldDark, textColor: Colors.white);
      _load();
    } else {
      Fluttertoast.showToast(msg: 'Could not delete', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _ScriptEditorScreen(existing: existing)),
    );
    if (saved == true) _load();
  }
}

// ── Script card (expandable + edit/delete menu) ──────────────────────────────
class _ScriptCard extends StatefulWidget {
  final Map<String, dynamic> script;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ScriptCard({required this.script, required this.onEdit, required this.onDelete});

  @override
  State<_ScriptCard> createState() => _ScriptCardState();
}

class _ScriptCardState extends State<_ScriptCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.script;
    final lines = ((s['lines'] as List?) ?? []).map((e) => e.toString()).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              child: Row(
                children: [
                  Container(
                    height: 40, width: 40,
                    decoration: BoxDecoration(color: kGoldDark.withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: const Icon(Icons.menu_book_rounded, color: kGoldDark, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${s['title'] ?? ''}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        if ((s['stage_label'] ?? '').toString().isNotEmpty)
                          Text('${s['stage_label']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => v == 'edit' ? widget.onEdit() : widget.onDelete(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final line in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right_rounded, size: 20, color: kGoldDark),
                          const SizedBox(width: 4),
                          Expanded(child: Text(line, style: const TextStyle(fontSize: 12.5, height: 1.35))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Add / Edit editor ────────────────────────────────────────────────────────
class _ScriptEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const _ScriptEditorScreen({this.existing});

  @override
  State<_ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends State<_ScriptEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _stageCtrl = TextEditingController();
  final List<TextEditingController> _lineCtrls = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = '${e['title'] ?? ''}';
      _stageCtrl.text = '${e['stage_label'] ?? ''}';
      for (final l in ((e['lines'] as List?) ?? [])) {
        _lineCtrls.add(TextEditingController(text: l.toString()));
      }
    }
    if (_lineCtrls.isEmpty) _lineCtrls.add(TextEditingController());
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _stageCtrl.dispose();
    for (final c in _lineCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit Script' : 'Add Script'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          _field(_titleCtrl, 'Title *', 'e.g. Opening / Introduction'),
          const SizedBox(height: 12),
          _field(_stageCtrl, 'Stage label', 'e.g. Opening'),
          const SizedBox(height: 18),
          Row(
            children: [
              const Text('Talking points', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => setState(() => _lineCtrls.add(TextEditingController())),
                icon: const Icon(Icons.add_rounded, size: 18, color: kGoldDark),
                label: const Text('Add line', style: TextStyle(color: kGoldDark, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < _lineCtrls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _lineCtrls[i],
                      decoration: InputDecoration(
                        hintText: 'Point ${i + 1}',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kGold)),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline_rounded, color: Colors.red.shade300),
                    onPressed: _lineCtrls.length == 1
                        ? null
                        : () => setState(() => _lineCtrls.removeAt(i).dispose()),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGoldDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.save_rounded),
              label: Text(_saving ? 'Saving…' : 'Save Script', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold)),
      ),
    );
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final lines = _lineCtrls.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (title.isEmpty) {
      Fluttertoast.showToast(msg: 'Title is required', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }
    if (lines.isEmpty) {
      Fluttertoast.showToast(msg: 'Add at least one talking point', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }
    setState(() => _saving = true);
    final ok = await ApiService.saveCallScript(
      id: widget.existing?['id'] as int?,
      title: title,
      stageLabel: _stageCtrl.text.trim().isEmpty ? null : _stageCtrl.text.trim(),
      lines: lines,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Fluttertoast.showToast(msg: _isEdit ? 'Script updated' : 'Script added', backgroundColor: kGoldDark, textColor: Colors.white);
      Navigator.pop(context, true);
    } else {
      Fluttertoast.showToast(msg: 'Could not save', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }
}
