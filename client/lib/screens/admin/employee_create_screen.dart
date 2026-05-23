import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';

class EmployeeCreateScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  const EmployeeCreateScreen({super.key, this.initialData});

  @override
  State<EmployeeCreateScreen> createState() => _EmployeeCreateScreenState();
}

class _EmployeeCreateScreenState extends State<EmployeeCreateScreen> {
  static const gold = Color(0xFFD7BE69);

  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _mobileCtrl   = TextEditingController();
  final _roleCtrl     = TextEditingController();
  final _pinCtrl      = TextEditingController();
  final _cityCtrl     = TextEditingController();
  final _stateCtrl    = TextEditingController();
  final _adminIdCtrl  = TextEditingController();
  final _latCtrl      = TextEditingController();
  final _lngCtrl      = TextEditingController();
  final _passCtrl     = TextEditingController();

  bool _isLocked      = false;
  bool _isSaving      = false;
  bool _isLocating    = false;
  bool _isFetchingPin = false;
  bool _obscurePass   = true;
  Map<String, String?> _fieldErrors = {};

  bool get _isEditing => widget.initialData != null;

  @override
  void initState() {
    super.initState();
    final d = widget.initialData;
    if (d != null) {
      _nameCtrl.text    = d['name']?.toString()     ?? '';
      _mobileCtrl.text  = (d['mobile'] ?? d['id'] ?? '').toString();
      _roleCtrl.text    = d['role']?.toString()     ?? '';
      _pinCtrl.text     = d['pincode']?.toString()  ?? '';
      _cityCtrl.text    = d['city']?.toString()     ?? '';
      _stateCtrl.text   = d['state']?.toString()    ?? '';
      _adminIdCtrl.text = d['admin_id']?.toString() ?? '';
      _latCtrl.text     = d['lat']?.toString()      ?? '';
      _lngCtrl.text     = d['lng']?.toString()      ?? '';
      _isLocked         = d['is_locked'] == true || d['is_locked'] == 1;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _mobileCtrl, _roleCtrl, _pinCtrl, _cityCtrl,
      _stateCtrl, _adminIdCtrl, _latCtrl, _lngCtrl, _passCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── pincode lookup ─────────────────────────────────────────────────────────

  Future<void> _fetchPincode(String pin) async {
    if (pin.length != 6) return;
    setState(() => _isFetchingPin = true);

    final result = await ApiService.lookupIndianPincode(pin);
    if (!mounted) return;

    if (result == null) {
      _showSnack('No data found for pincode $pin');
    } else {
      final city  = (result['city']  as String?)?.trim() ?? '';
      final state = (result['state'] as String?)?.trim() ?? '';
      setState(() {
        if (city.isNotEmpty)  _cityCtrl.text  = city;
        if (state.isNotEmpty) _stateCtrl.text = state;
      });
      if (city.isNotEmpty || state.isNotEmpty) {
        _showSnack('Auto-filled: $city${city.isNotEmpty && state.isNotEmpty ? ', ' : ''}$state');
      }
    }
    setState(() => _isFetchingPin = false);
  }

  // ── geo location ───────────────────────────────────────────────────────────

  Future<void> _getLocation() async {
    setState(() => _isLocating = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location services disabled. Please enable GPS.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Location permission denied.');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack('Location permission permanently denied. Enable in app settings.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(6);
        _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      });
    } catch (e) {
      _showSnack('Could not get location.');
    } finally {
      setState(() => _isLocating = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  // ── save ───────────────────────────────────────────────────────────────────

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

    final adminId = _adminIdCtrl.text.trim();
    if (adminId.isNotEmpty) payload['admin_id'] = int.tryParse(adminId);

    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    if (lat != null) payload['lat'] = lat;
    if (lng != null) payload['lng'] = lng;

    final pass = _passCtrl.text;
    if (pass.isNotEmpty) payload['password'] = pass;

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
      _showSnack('Failed to save. Please try again.');
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
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

              // ── Basic Info ──────────────────────────────────────────────
              _sectionCard('Basic Info', Icons.person_outline_rounded, [
                _field(
                  _nameCtrl, 'Full Name *', Icons.person_outline_rounded,
                  errorKey: 'name',
                  caps: TextCapitalization.words,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Full name is required';
                    if (v.trim().length < 2) return 'Name must be at least 2 characters';
                    return null;
                  },
                ),
                _gap,
                _field(
                  _mobileCtrl, 'Mobile Number *', Icons.phone_outlined,
                  errorKey: 'mobile',
                  readOnly: _isEditing,
                  helper: _isEditing ? 'Mobile cannot be changed' : null,
                  keyboard: TextInputType.phone,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Mobile number is required';
                    if (v.trim().length != 10) return 'Must be exactly 10 digits';
                    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(v.trim())) return 'Enter a valid Indian mobile number';
                    return null;
                  },
                ),
                _gap,
                _field(
                  _roleCtrl, 'Role *', Icons.badge_outlined,
                  errorKey: 'role',
                  caps: TextCapitalization.words,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Role is required';
                    return null;
                  },
                ),
                _gap,
                _field(
                  _adminIdCtrl, 'Admin ID', Icons.admin_panel_settings_outlined,
                  errorKey: 'admin_id',
                  keyboard: TextInputType.number,
                  formatters: [FilteringTextInputFormatter.digitsOnly],
                  helper: 'Optional — numeric ID of the assigned admin',
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (int.tryParse(v.trim()) == null) return 'Must be a valid number';
                    return null;
                  },
                ),
              ]),

              _vgap,

              // ── Address ─────────────────────────────────────────────────
              _sectionCard('Address', Icons.location_city_outlined, [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _pincodeField(),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: _field(
                        _cityCtrl, 'City', Icons.location_city_outlined,
                        errorKey: 'city',
                        caps: TextCapitalization.words,
                        validator: (v) {
                          if (v != null && v.trim().isNotEmpty && v.trim().length < 2) return 'Too short';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                _gap,
                _field(
                  _stateCtrl, 'State', Icons.map_outlined,
                  errorKey: 'state',
                  caps: TextCapitalization.words,
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty && v.trim().length < 2) return 'Too short';
                    return null;
                  },
                ),
              ]),

              _vgap,

              // ── Geo Location ────────────────────────────────────────────
              _sectionCard('Geo Location', Icons.my_location_rounded, [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        _latCtrl, 'Latitude', Icons.north_rounded,
                        errorKey: 'lat',
                        keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v.trim());
                          if (n == null) return 'Invalid number';
                          if (n < -90 || n > 90) return 'Range: -90 to 90';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _lngCtrl, 'Longitude', Icons.east_rounded,
                        errorKey: 'lng',
                        keyboard: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return null;
                          final n = double.tryParse(v.trim());
                          if (n == null) return 'Invalid number';
                          if (n < -180 || n > 180) return 'Range: -180 to 180';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLocating ? null : _getLocation,
                    icon: _isLocating
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: gold))
                        : const Icon(Icons.my_location_rounded, color: gold),
                    label: Text(
                      _isLocating ? 'Fetching location…' : 'Get Current Location',
                      style: const TextStyle(color: gold, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: gold),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ]),

              _vgap,

              // ── Password ────────────────────────────────────────────────
              _sectionCard(
                _isEditing ? 'Change Password' : 'Password',
                Icons.lock_outline_rounded,
                [
                  if (_isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Leave blank to keep the current password',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                      ),
                    ),
                  _passwordField(
                    _passCtrl,
                    _isEditing ? 'New Password' : 'Password *',
                    _obscurePass,
                    onToggle: () => setState(() => _obscurePass = !_obscurePass),
                    errorKey: 'password',
                    validator: (v) {
                      if (!_isEditing && (v == null || v.trim().isEmpty)) return 'Password is required';
                      if (v != null && v.isNotEmpty && v.length < 6) return 'Password must be at least 6 characters';
                      return null;
                    },
                  ),
                ],
              ),

              _vgap,

              // ── Account Status ───────────────────────────────────────────
              _sectionCard('Account Status', Icons.shield_outlined, [
                Row(
                  children: [
                    Icon(
                      _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                      size: 20,
                      color: _isLocked ? Colors.red : Colors.green,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isLocked ? 'Account Locked' : 'Account Active',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _isLocked ? Colors.red : Colors.green.shade700,
                            ),
                          ),
                          Text(
                            _isLocked ? 'Employee cannot log in' : 'Employee can log in normally',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: _isLocked,
                      activeThumbColor: Colors.red,
                      activeTrackColor: Colors.red.shade200,
                      inactiveThumbColor: Colors.green,
                      inactiveTrackColor: Colors.green.shade100,
                      onChanged: (v) => setState(() => _isLocked = v),
                    ),
                  ],
                ),
              ]),

              const SizedBox(height: 16),

              SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(_isEditing ? Icons.save_rounded : Icons.person_add_alt_1_rounded),
                  label: Text(_isSaving ? 'Saving…' : (_isEditing ? 'Save Changes' : 'Create Employee')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: gold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: gold.withValues(alpha: 0.6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── widgets ────────────────────────────────────────────────────────────────

  static const _gap  = SizedBox(height: 10);
  static const _vgap = SizedBox(height: 12);

  Widget _pincodeField() {
    return TextFormField(
      controller: _pinCtrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      onChanged: (v) { if (v.trim().length == 6) _fetchPincode(v.trim()); },
      validator: (v) {
        if (v == null || v.trim().isEmpty) return null;
        if (v.trim().length != 6) return 'Must be 6 digits';
        return null;
      },
      decoration: InputDecoration(
        labelText: 'Pincode',
        errorText: _fieldErrors['pincode'],
        prefixIcon: const Icon(Icons.pin_drop_outlined, size: 20),
        suffixIcon: _isFetchingPin
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: gold)),
              )
            : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border:             _border(Colors.grey.shade300),
        enabledBorder:      _border(Colors.grey.shade300),
        focusedBorder:      _border(gold),
        errorBorder:        _border(Colors.red.shade300),
        focusedErrorBorder: _border(Colors.red),
      ),
    );
  }

  Widget _sectionCard(String title, IconData icon, List<Widget> children) {
    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: gold),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF5A5A5A))),
            ]),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  OutlineInputBorder _border(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c));

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    required String errorKey,
    bool readOnly = false,
    String? helper,
    TextInputType? keyboard,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return TextFormField(
      controller: ctrl,
      readOnly: readOnly,
      keyboardType: keyboard,
      inputFormatters: formatters,
      textCapitalization: caps,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        errorText: _fieldErrors[errorKey],
        prefixIcon: Icon(icon, size: 20),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF0F0F0) : null,
        border:             _border(Colors.grey.shade300),
        enabledBorder:      _border(Colors.grey.shade300),
        focusedBorder:      _border(gold),
        errorBorder:        _border(Colors.red.shade300),
        focusedErrorBorder: _border(Colors.red),
      ),
    );
  }

  Widget _passwordField(
    TextEditingController ctrl,
    String label,
    bool obscure, {
    required VoidCallback onToggle,
    String? errorKey,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorKey != null ? _fieldErrors[errorKey] : null,
        prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
          onPressed: onToggle,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border:             _border(Colors.grey.shade300),
        enabledBorder:      _border(Colors.grey.shade300),
        focusedBorder:      _border(gold),
        errorBorder:        _border(Colors.red.shade300),
        focusedErrorBorder: _border(Colors.red),
      ),
    );
  }
}
