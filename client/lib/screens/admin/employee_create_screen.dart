import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';

class EmployeeCreateScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const EmployeeCreateScreen({super.key, this.initialData});

  @override
  State<EmployeeCreateScreen> createState() => _EmployeeCreateScreenState();
}

class _EmployeeCreateScreenState extends State<EmployeeCreateScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _nameCtrl   = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _roleCtrl   = TextEditingController();
  final _pinCtrl    = TextEditingController();
  final _cityCtrl   = TextEditingController();
  final _stateCtrl  = TextEditingController();

  bool _isLocked = false;
  bool _isSaving = false;
  Map<String, String?> _fieldErrors = {};

  bool get _isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      _nameCtrl.text   = d['name']?.toString()    ?? '';
      _mobileCtrl.text = (d['mobile'] ?? d['id'] ?? '').toString();
      _roleCtrl.text   = d['role']?.toString()    ?? '';
      _pinCtrl.text    = d['pincode']?.toString() ?? '';
      _cityCtrl.text   = d['city']?.toString()    ?? '';
      _stateCtrl.text  = d['state']?.toString()   ?? '';
      _isLocked        = d['is_locked'] == true || d['is_locked'] == 1;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _mobileCtrl.dispose(); _roleCtrl.dispose();
    _pinCtrl.dispose(); _cityCtrl.dispose(); _stateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _isSaving = true; _fieldErrors = {}; });

    final payload = <String, dynamic>{
      'name'      : _nameCtrl.text.trim(),
      'mobile'    : _mobileCtrl.text.trim(),
      'role'      : _roleCtrl.text.trim(),
      'pincode'   : _pinCtrl.text.trim(),
      'city'      : _cityCtrl.text.trim(),
      'state'     : _stateCtrl.text.trim(),
      'is_locked' : _isLocked,
    };

    Map<String, dynamic>? res;
    if (_isEditing) {
      final id = (widget.initialData!['mobile'] ?? widget.initialData!['id']).toString();
      res = await ApiService.updateEmployee(id, payload);
    } else {
      res = await ApiService.createEmployee(payload);
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res != null && res.containsKey('errors')) {
      final errors = Map<String, dynamic>.from(res['errors'] as Map);
      setState(() {
        _fieldErrors = errors.map((k, v) {
          if (v is List && v.isNotEmpty) return MapEntry(k, v.first.toString());
          return MapEntry(k, v.toString());
        });
      });
      return;
    }

    if (res != null) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD7BE69);

    OutlineInputBorder border(Color c) =>
        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c));

    InputDecoration dec(String label, {IconData? icon, bool readOnly = false, String? errorText, String? helper}) =>
        InputDecoration(
          labelText: label,
          errorText: errorText,
          helperText: helper,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          filled: readOnly,
          fillColor: readOnly ? const Color(0xFFF0F0F0) : null,
          border: border(Colors.grey.shade300),
          enabledBorder: border(Colors.grey.shade300),
          focusedBorder: border(gold),
          errorBorder: border(Colors.red.shade300),
          focusedErrorBorder: border(Colors.red),
        );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Employee' : 'Create Employee'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.white,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: dec('Full Name *', icon: Icons.person_outline_rounded, errorText: _fieldErrors['name']),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 10),

                      // Mobile
                      TextFormField(
                        controller: _mobileCtrl,
                        keyboardType: TextInputType.phone,
                        readOnly: _isEditing,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: dec(
                          'Mobile Number *',
                          icon: Icons.phone_outlined,
                          readOnly: _isEditing,
                          errorText: _fieldErrors['mobile'],
                          helper: _isEditing ? 'Cannot be changed' : null,
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Required';
                          if (v.trim().length < 10) return 'Enter 10-digit number';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),

                      // Role
                      TextFormField(
                        controller: _roleCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: dec('Role', icon: Icons.badge_outlined, errorText: _fieldErrors['role']),
                      ),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),

                      // Pincode + City row
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _pinCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              decoration: dec('Pincode', icon: Icons.pin_drop_outlined, errorText: _fieldErrors['pincode']),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _cityCtrl,
                              textCapitalization: TextCapitalization.words,
                              decoration: dec('City', icon: Icons.location_city_outlined, errorText: _fieldErrors['city']),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // State
                      TextFormField(
                        controller: _stateCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: dec('State', icon: Icons.map_outlined, errorText: _fieldErrors['state']),
                      ),

                      const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),

                      // Lock toggle
                      Row(
                        children: [
                          Icon(
                            _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                            size: 20,
                            color: _isLocked ? Colors.red : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _isLocked ? 'Account Locked' : 'Account Active',
                              style: TextStyle(fontSize: 14, color: _isLocked ? Colors.red : Colors.black87),
                            ),
                          ),
                          Switch.adaptive(
                            value: _isLocked,
                            activeThumbColor: Colors.red,
                            activeTrackColor: Colors.red.shade200,
                            onChanged: (v) => setState(() => _isLocked = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(_isEditing ? Icons.save_rounded : Icons.person_add_alt_1_rounded),
                  label: Text(_isSaving ? 'Saving...' : (_isEditing ? 'Save Changes' : 'Create Employee')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: gold.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
