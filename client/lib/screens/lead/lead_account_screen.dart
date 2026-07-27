import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';

class LeadAccountScreen extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? leadId;

  const LeadAccountScreen({super.key, this.initialData, this.leadId});

  @override
  State<LeadAccountScreen> createState() => _LeadAccountScreenState();
}

class _LeadAccountScreenState extends State<LeadAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  // Text controllers
  final _contactCtrl  = TextEditingController();
  final _bizNameCtrl  = TextEditingController();
  final _personCtrl   = TextEditingController();
  final _gstCtrl      = TextEditingController();
  final _panCtrl      = TextEditingController();
  final _pincodeCtrl  = TextEditingController();
  final _countryCtrl  = TextEditingController();
  final _stateCtrl    = TextEditingController();
  final _districtCtrl = TextEditingController();
  final _cityCtrl     = TextEditingController();
  final _areaCtrl     = TextEditingController();
  final _addressCtrl  = TextEditingController();

  // Dropdowns
  String? _bizType;
  String? _bizSize;
  String? _custStage;
  String? _funnelStage;

  // Toggles & loading
  bool    _isActive         = true;
  bool    _isLoading        = false;
  bool    _locationCaptured = false;
  double? _latitude;
  double? _longitude;
  String  _locationText     = '';

  // Images
  String? _shopImage;
  String? _ownerImage;

  // Contact existence check
  bool                    _checkingContact  = false;
  bool                    _lookingUpPincode = false;
  String?                 _contactExistsMsg;
  Map<String, dynamic>?   _existingAccount;   // full data returned by check-contact
  Timer?                  _debounceTimer;
  List<String>            _pincodeAreas = [];

  // Server-side field errors
  Map<String, String> _fieldErrors = {};

  bool    get _isEditMode => widget.initialData != null || (widget.leadId?.isNotEmpty ?? false);
  String? get _editId {
    final raw = widget.initialData?['id'];
    if (raw == null) return widget.leadId;
    final id = raw.toString().trim();
    return id.isEmpty ? widget.leadId : id;
  }

  String _str(Map<String, dynamic> d, String key) {
    final v = d[key];
    if (v == null) return '';
    return v.toString();
  }

  bool _bool(Map<String, dynamic> d, String key, {bool fallback = true}) {
    final v = d[key];
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1') return true;
      if (s == 'false' || s == '0') return false;
    }
    return fallback;
  }

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _contactCtrl.addListener(_onContactChanged);
    if (widget.initialData != null) {
      _populateFromData(widget.initialData!);
    } else if (_isEditMode && _editId != null) {
      _loadEditData(_editId!);
    }
  }

  Future<void> _loadEditData(String id) async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.getLeadAccount(id);
      if (!mounted) return;
      if (data == null) {
        _showSnack('Could not load lead account data');
        return;
      }
      _populateFromData(data);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _populateFromData(Map<String, dynamic> d) {
    _contactCtrl.text  = _str(d, 'contactNumber');
    _bizNameCtrl.text  = _str(d, 'businessName');
    _personCtrl.text   = _str(d, 'personName');
    _gstCtrl.text      = _str(d, 'gstNumber');
    _panCtrl.text      = _str(d, 'panCard');
    _pincodeCtrl.text  = _str(d, 'pincode');
    _countryCtrl.text  = _str(d, 'country');
    _stateCtrl.text    = _str(d, 'state');
    _districtCtrl.text = _str(d, 'district');
    _cityCtrl.text     = _str(d, 'city');
    _areaCtrl.text     = _str(d, 'area');
    _addressCtrl.text  = _str(d, 'address');
    _bizType     = _str(d, 'businessType').isEmpty ? null : _str(d, 'businessType');
    _bizSize     = _str(d, 'businessSize').isEmpty ? null : _str(d, 'businessSize');
    _custStage   = _str(d, 'customerStage').isEmpty ? null : _str(d, 'customerStage');
    _funnelStage = _str(d, 'funnelStage').isEmpty ? null : _str(d, 'funnelStage');
    _isActive    = _bool(d, 'isActive', fallback: true);
    _shopImage   = _str(d, 'shopImage').isEmpty ? null : _str(d, 'shopImage');
    _ownerImage  = _str(d, 'ownerImage').isEmpty ? null : _str(d, 'ownerImage');

    final lat = d['latitude'];
    final lng = d['longitude'];
    final latNum = lat is num ? lat.toDouble() : double.tryParse(lat?.toString() ?? '');
    final lngNum = lng is num ? lng.toDouble() : double.tryParse(lng?.toString() ?? '');
    if (latNum != null && lngNum != null) {
      _latitude         = latNum;
      _longitude        = lngNum;
      _locationCaptured = true;
      _locationText     = '${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}';
    }

    final pin = _pincodeCtrl.text.trim();
    if (pin.length == 6) {
      _lookupPincode(silent: true, keepAreaSelection: true);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _contactCtrl.removeListener(_onContactChanged);
    for (final c in [
      _contactCtrl, _bizNameCtrl, _personCtrl, _gstCtrl, _panCtrl,
      _pincodeCtrl, _countryCtrl, _stateCtrl, _districtCtrl,
      _cityCtrl, _areaCtrl, _addressCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Contact auto-check ──────────────────────────────────────────────────────

  void _onContactChanged() {
    final number = _contactCtrl.text.trim();

    _debounceTimer?.cancel();

    if (!_mobileRegex.hasMatch(number)) {
      // Clear stale result as user edits back to an incomplete/invalid number
      if (_contactExistsMsg != null || _existingAccount != null || _checkingContact) {
        setState(() {
          _contactExistsMsg = null;
          _existingAccount  = null;
          _checkingContact  = false;
        });
      }
      return;
    }

    // Fire after 500 ms of no further typing
    _debounceTimer = Timer(const Duration(milliseconds: 500), _checkContactExists);
  }

  Future<void> _checkContactExists() async {
    final number = _contactCtrl.text.trim();
    if (!_mobileRegex.hasMatch(number)) return;

    setState(() {
      _checkingContact  = true;
      _contactExistsMsg = null;
      _existingAccount  = null;
    });

    final result = await ApiService.checkLeadContactExists(
      number,
      excludeId: _isEditMode ? _editId : null,
    );

    if (!mounted) return;

    if (result != null && result['exists'] == true) {
      final data = result['data'] as Map<String, dynamic>?;
      setState(() {
        _checkingContact  = false;
        _existingAccount  = data;
        _contactExistsMsg = 'Contact number is already registered';
      });
    } else {
      setState(() {
        _checkingContact  = false;
        _existingAccount  = null;
        _contactExistsMsg = null;
      });
    }
  }

  // ── Existing-account actions (from banner) ──────────────────────────────────

  Future<void> _viewExisting() async {
    final acc = _existingAccount;
    if (acc == null) return;
    final id = acc['id']?.toString() ?? '';
    final full = await ApiService.getLeadAccount(id);
    if (!mounted) return;
    context.push('/lead-accounts/$id', extra: full ?? acc);
  }

  Future<void> _editExisting() async {
    final acc = _existingAccount;
    if (acc == null) return;
    final id = acc['id']?.toString() ?? '';
    final full = await ApiService.getLeadAccount(id);
    if (!mounted) return;
    context.push('/lead-accounts/$id/edit', extra: full ?? acc);
  }

  Future<void> _deleteExisting() async {
    final acc = _existingAccount;
    if (acc == null) return;
    final id      = acc['id']?.toString() ?? '';
    final bizName = acc['businessName']?.toString() ?? 'this account';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Account', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Delete "$bizName"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ApiService.deleteLeadAccount(id);
    if (!mounted) return;

    if (ok) {
      setState(() {
        _contactExistsMsg = null;
        _existingAccount  = null;
      });
      _showSnack('Account deleted successfully');
    } else {
      _showSnack('Delete failed — please try again');
    }
  }

  // ── Validation helpers ──────────────────────────────────────────────────────

  static final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]{1}$', caseSensitive: false);

  static final _mobileRegex = RegExp(r'^[6-9][0-9]{9}$');

  String? _validateContact(String? v) {
    final number = (v ?? '').trim();
    if (number.isEmpty)               return 'Contact number is required';
    if (number.length != 10)          return 'Must be exactly 10 digits';
    if (!_mobileRegex.hasMatch(number)) return 'Enter a valid mobile number';
    if (_contactExistsMsg != null)     return _contactExistsMsg;
    return null;
  }

  String? _validateRequired(String? v, String label) {
    if (v == null || v.trim().isEmpty) return '$label is required';
    if (v.trim().length < 2)           return '$label must be at least 2 characters';
    return null;
  }

  String? _validateGst(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return null;
  }

  String? _validatePan(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    if (v.trim().length != 10)         return 'PAN must be exactly 10 characters';
    if (!_panRegex.hasMatch(v.trim())) return 'Invalid PAN format (e.g. ABCDE1234F)';
    return null;
  }

  String? _validatePincode(String? v) {
    if (v == null || v.trim().isEmpty) return 'Pincode is required';
    if (v.trim().length != 6)          return 'Pincode must be exactly 6 digits';
    return null;
  }

  // ── Other actions ───────────────────────────────────────────────────────────
  Future<void> _lookupPincode({
    bool silent = false,
    bool keepAreaSelection = false,
  }) async {
    final pin = _pincodeCtrl.text.trim();
    if (pin.length < 6) {
      if (!silent) _showSnack('Enter a valid 6-digit pincode');
      return;
    }

    setState(() => _lookingUpPincode = true);
    if (!silent) _showSnack('Looking up $pin...');

    final result = await ApiService.lookupIndianPincode(pin);
    if (!mounted) return;

    if (result == null) {
      setState(() {
        _lookingUpPincode = false;
        _pincodeAreas = [];
      });
      if (!silent) _showSnack('No pincode data found');
      return;
    }

    final areas = List<String>.from(result['areas'] as List? ?? const <String>[]);
    final selectedArea = _areaCtrl.text.trim();

    setState(() {
      _countryCtrl.text = (result['country'] as String?)?.trim().isNotEmpty == true
          ? (result['country'] as String).trim()
          : 'India';
      _stateCtrl.text = (result['state'] as String?)?.trim() ?? '';
      _districtCtrl.text = (result['district'] as String?)?.trim() ?? '';
      _cityCtrl.text = (result['city'] as String?)?.trim() ?? '';
      _pincodeAreas = areas;

      if (_pincodeAreas.isNotEmpty) {
        if (keepAreaSelection && selectedArea.isNotEmpty && _pincodeAreas.contains(selectedArea)) {
          _areaCtrl.text = selectedArea;
        } else {
          _areaCtrl.text = _pincodeAreas.first;
        }
      }
      _lookingUpPincode = false;
    });

    if (!silent) _showSnack('Pincode details loaded');
  }

  Future<void> _captureLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Please enable location service');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _showSnack('Location permission denied');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;

      setState(() {
        _locationCaptured = true;
        _latitude = pos.latitude;
        _longitude = pos.longitude;
        _locationText = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      });
      _showSnack('Location captured');
    } catch (_) {
      if (!mounted) return;
      _showSnack('Could not capture location');
    }
  }

  Future<ImageSource?> _askImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(bool isShop) async {
    final source = await _askImageSource();
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1800,
      );
    } on MissingPluginException {
      if (!mounted) return;
      _showSnack('Image picker plugin not ready. Please restart app.');
      return;
    } on PlatformException catch (e) {
      if (!mounted) return;
      _showSnack('Unable to pick image: ${e.message ?? 'permission denied or cancelled'}');
      return;
    } catch (e) {
      if (!mounted) return;
      _showSnack('Unable to pick image. Please try again.');
      debugPrint('pickImage error: $e');
      return;
    }

    if (picked == null || !mounted) return;

    try {
      _showSnack('Uploading image...');
      final bytes = await picked.readAsBytes();
      final uploadedPath = await ApiService.uploadLeadImage(bytes, picked.name);
      if (!mounted) return;
      if (uploadedPath == null || uploadedPath.trim().isEmpty) {
        _showSnack('Image upload failed. Check API URL/network and try again.');
        return;
      }

      setState(() {
        if (isShop) {
          _shopImage = uploadedPath;
        } else {
          _ownerImage = uploadedPath;
        }
      });
      _showSnack('Image uploaded');
    } catch (e) {
      if (!mounted) return;
      _showSnack('Image upload failed. Please try again.');
      debugPrint('uploadImage error: $e');
    }
  }

  Future<void> _submit() async {
    // Ensure check has run before validating
    if (_checkingContact) {
      _showSnack('Verifying contact number…');
      return;
    }
    if (_mobileRegex.hasMatch(_contactCtrl.text.trim()) && _existingAccount == null && _contactExistsMsg == null) {
      await _checkContactExists();
      if (!mounted) return;
    }

    setState(() => _fieldErrors = {});
    if (!_formKey.currentState!.validate()) return;
    if (_contactExistsMsg != null) {
      _showSnack('Contact number is already registered');
      return;
    }

    setState(() => _isLoading = true);

    final body = <String, dynamic>{
      'businessName':   _bizNameCtrl.text.trim(),
      'businessType':   _bizType!,
      'businessSize':   _bizSize!,
      'personName':     _personCtrl.text.trim(),
      'contactNumber':  _contactCtrl.text.trim(),
      'customerStage':  _custStage!,
      'funnelStage':    _funnelStage!,
      'area':           _areaCtrl.text.trim(),
      'pincode':        _pincodeCtrl.text.trim(),
      'isActive':       _isActive,
      if (_gstCtrl.text.trim().isNotEmpty)      'gstNumber': _gstCtrl.text.trim().toUpperCase(),
      if (_panCtrl.text.trim().isNotEmpty)      'panCard':   _panCtrl.text.trim().toUpperCase(),
      if (_countryCtrl.text.trim().isNotEmpty)  'country':   _countryCtrl.text.trim(),
      if (_stateCtrl.text.trim().isNotEmpty)    'state':     _stateCtrl.text.trim(),
      if (_districtCtrl.text.trim().isNotEmpty) 'district':  _districtCtrl.text.trim(),
      if (_cityCtrl.text.trim().isNotEmpty)     'city':      _cityCtrl.text.trim(),
      if (_addressCtrl.text.trim().isNotEmpty)  'address':   _addressCtrl.text.trim(),
      if (_latitude  != null) 'latitude':  _latitude,
      if (_longitude != null) 'longitude': _longitude,
      if (_shopImage  != null) 'shopImage':  _shopImage,
      if (_ownerImage != null) 'ownerImage': _ownerImage,
      if (!_isEditMode && (UserService.currentMobile ?? '').isNotEmpty)
        'createdById': UserService.currentMobile,
    };

    try {
      final result = _isEditMode && _editId != null
          ? await ApiService.updateLeadAccount(_editId!, body)
          : await ApiService.createLeadAccount(body);

      if (!mounted) return;

      if (result == null) { _showSnack('Network error — please try again'); return; }

      if (result.containsKey('errors')) {
        final raw  = result['errors'];
        final errs = <String, String>{};
        if (raw is Map) {
          raw.forEach((k, v) => errs[k.toString()] = (v is List ? v.first : v).toString());
        } else {
          errs['_general'] = raw.toString();
        }
        setState(() => _fieldErrors = errs);
        _showSnack('Please fix the highlighted errors');
        return;
      }

      _showSnack(_isEditMode ? 'Lead account updated!' : 'Lead account created!');
      if (mounted) context.pop(true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clear() {
    _debounceTimer?.cancel();
    _formKey.currentState!.reset();
    setState(() {
      _bizType = null; _bizSize = null;
      _custStage = null; _funnelStage = null;
      _isActive = true;
      _shopImage = null; _ownerImage = null;
      _locationCaptured = false; _locationText = '';
      _latitude = null; _longitude = null;
      _fieldErrors      = {};
      _contactExistsMsg = null;
      _existingAccount  = null;
      _checkingContact  = false;
      _lookingUpPincode = false;
      _pincodeAreas     = [];
    });
    for (final c in [
      _contactCtrl, _bizNameCtrl, _personCtrl, _gstCtrl, _panCtrl,
      _pincodeCtrl, _countryCtrl, _stateCtrl, _districtCtrl,
      _cityCtrl, _areaCtrl, _addressCtrl,
    ]) { c.clear(); }
  }

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ── UI helpers ───────────────────────────────────────────────────────────────

  static const gold      = Color(0xFFD7BE69);
  static const goldLight = Color(0xFFFFF8EE);

  OutlineInputBorder _border(Color c) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c),
  );

  InputDecoration _dec(String label, {IconData? icon, Widget? suffix}) => InputDecoration(
    labelText: label,
    prefixIcon:  icon   != null ? Icon(icon, size: 20, color: gold) : null,
    suffixIcon:  suffix,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    filled: true,
    fillColor: Colors.white,
    border:             _border(Colors.grey.shade300),
    enabledBorder:      _border(Colors.grey.shade300),
    focusedBorder:      _border(gold),
    errorBorder:        _border(Colors.red.shade300),
    focusedErrorBorder: _border(Colors.red),
    labelStyle: const TextStyle(color: Colors.grey),
  );

  Widget _sectionHeader(IconData icon, String title) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(color: goldLight, borderRadius: BorderRadius.circular(10)),
    child: Row(children: [
      Icon(icon, size: 18, color: gold),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: gold)),
    ]),
  );

  Widget _gap() => const SizedBox(height: 10);

  Widget _dropdown(
    String label, IconData icon, List<String> items, String? value,
    void Function(String?) onChanged, {
    bool required = false, String? fieldKey,
  }) {
    final serverErr = fieldKey != null ? _fieldErrors[fieldKey] : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: _dec(label, icon: icon),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: gold),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
        onChanged: onChanged,
        validator: required ? (v) => v == null ? 'Please select an option' : null : null,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
      ),
      if (serverErr != null)
        Padding(
          padding: const EdgeInsets.only(left: 12, top: 4),
          child: Text(serverErr, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ),
    ]);
  }

  Widget _textField(
    String label, TextEditingController ctrl, {
    IconData? icon, TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    TextCapitalization capitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    String? fieldKey, Widget? suffix,
  }) {
    final serverErr = fieldKey != null ? _fieldErrors[fieldKey] : null;
    return TextFormField(
      controller:         ctrl,
      keyboardType:       keyboardType,
      inputFormatters:    formatters,
      textCapitalization: capitalization,
      decoration: _dec(label, icon: icon, suffix: suffix).copyWith(
        errorText:     serverErr,
        errorMaxLines: 2,
      ),
      validator: validator,
    );
  }

  Widget _areaField() {
    final serverErr = _fieldErrors['area'];
    if (_pincodeAreas.isEmpty) {
      return _textField(
        'Main Area *',
        _areaCtrl,
        icon: Icons.home_rounded,
        validator: (v) => _validateRequired(v, 'Area'),
        fieldKey: 'area',
      );
    }

    final current = _areaCtrl.text.trim();
    final value = _pincodeAreas.contains(current) ? current : null;
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: _dec('Main Area *', icon: Icons.home_rounded).copyWith(
        errorText: serverErr,
        errorMaxLines: 2,
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: gold),
      items: _pincodeAreas
          .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14))))
          .toList(),
      onChanged: (v) {
        if (v == null) return;
        setState(() => _areaCtrl.text = v);
      },
      validator: (v) => _validateRequired(v, 'Area'),
      style: const TextStyle(fontSize: 14, color: Colors.black87),
    );
  }

  // Suffix icon for the contact field
  Widget _contactSuffix() {
    if (_checkingContact) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: gold)),
      );
    }
    if (_contactExistsMsg != null) return const Icon(Icons.warning_amber_rounded, color: Colors.red);
    if (_mobileRegex.hasMatch(_contactCtrl.text.trim())) return const Icon(Icons.check_circle_rounded, color: Colors.green);
    return const SizedBox.shrink();
  }

  // "Already exists" banner with View / Edit / Delete actions
  Widget _existsBanner() {
    final acc = _existingAccount;
    if (_contactExistsMsg == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Message row
        Row(children: [
          const Icon(Icons.info_outline_rounded, color: Colors.red, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _contactExistsMsg!,
              style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ]),

        if (acc != null) ...[
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFFFCDD2)),
          const SizedBox(height: 10),

          // Existing-account detail rows
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade100),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${acc['businessName'] ?? 'Unnamed business'}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.black87)),
              const SizedBox(height: 6),
              _existingInfoRow(Icons.badge_rounded, 'Account code', acc['accountCode']?.toString()),
              _existingInfoRow(Icons.person_outline_rounded, 'Person', acc['personName']?.toString()),
              _existingInfoRow(Icons.store_rounded, 'Business type', acc['businessType']?.toString()),
              _existingInfoRow(Icons.flag_rounded, 'Stage', acc['customerStage']?.toString()),
              _existingInfoRow(Icons.location_on_rounded, 'Location',
                  [acc['area'], acc['city']].where((s) => (s ?? '').toString().trim().isNotEmpty).join(', ')),
            ]),
          ),

          const SizedBox(height: 10),
          // Action buttons row
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _bannerBtn(Icons.visibility_rounded, 'View', Colors.blue, _viewExisting),
            const SizedBox(width: 8),
            _bannerBtn(Icons.edit_rounded, 'Edit', gold, _editExisting),
            const SizedBox(width: 8),
            _bannerBtn(Icons.delete_rounded, 'Delete', Colors.red, _deleteExisting),
          ]),
        ],
      ]),
    );
  }

  Widget _existingInfoRow(IconData icon, String label, String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
        Expanded(child: Text(v, style: const TextStyle(fontSize: 11.5, color: Colors.black87))),
      ]),
    );
  }

  Widget _bannerBtn(IconData icon, String label, Color color, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            border: Border.all(color: color.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
          ]),
        ),
      );

  Widget _imageTile(String label, bool isShop, String? imageValue) {
    final raw = (imageValue ?? '').trim();
    final hasValue = raw.isNotEmpty;
    final isHttp = raw.startsWith('http://') || raw.startsWith('https://');
    final isRelativeServerPath = raw.startsWith('/');
    final networkUrl = isHttp
        ? raw
        : (isRelativeServerPath ? '${ApiConfig.baseUrl}$raw' : null);
    final localPath = (!isHttp && !isRelativeServerPath && hasValue) ? raw : null;

    Widget placeholder({bool showSelected = false}) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          showSelected ? Icons.check_circle_rounded : Icons.add_photo_alternate_rounded,
          size: 30,
          color: showSelected ? Colors.green : gold,
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
        const SizedBox(height: 2),
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.camera_alt_outlined, size: 13, color: Colors.grey),
          SizedBox(width: 4),
          Icon(Icons.folder_outlined, size: 13, color: Colors.grey),
          SizedBox(width: 4),
          Text('Tap to select', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]),
      ],
    );

    return Expanded(
      child: GestureDetector(
        onTap: () => _pickImage(isShop),
        child: Container(
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: hasValue ? gold : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(10),
          ),
          child: networkUrl != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    networkUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => placeholder(),
                  ),
                )
              : localPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        File(localPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => placeholder(),
                      ),
                    )
                  : placeholder(showSelected: hasValue),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final generalErr = _fieldErrors['_general'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_isEditMode ? 'Edit Lead Account' : 'New Lead Account'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: Stack(children: [
        Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

              // General server error
              if (generalErr != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    border: Border.all(color: Colors.red.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(generalErr, style: const TextStyle(color: Colors.red)),
                ),

              // ── Business Information ──────────────────────────────────
              _sectionHeader(Icons.business_rounded, 'Business Information'),
              const SizedBox(height: 10),

              // Contact number — auto-checks at 10 digits
              TextFormField(
                controller: _contactCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: _dec('Contact Number *',
                  icon: Icons.phone_rounded,
                  suffix: _contactSuffix(),
                ).copyWith(
                  errorText: _fieldErrors['contactNumber'],
                  errorMaxLines: 2,
                ),
                validator: _validateContact,
              ),

              // Exists banner with View / Edit / Delete
              _existsBanner(),

              _gap(),

              _textField('Business Name *', _bizNameCtrl,
                  icon: Icons.store_rounded,
                  capitalization: TextCapitalization.words,
                  validator: (v) => _validateRequired(v, 'Business name'),
                  fieldKey: 'businessName'),
              _gap(),

              _dropdown('Business Type *', Icons.account_tree_rounded,
                  ['Retail', 'Wholesale', 'Manufacturer', 'Service', 'Distributor', 'Other'],
                  _bizType, (v) => setState(() => _bizType = v),
                  required: true, fieldKey: 'businessType'),
              _gap(),

              _dropdown('Business Size *', Icons.group_work_rounded,
                  ['Micro', 'Small', 'Medium', 'Large', 'Enterprise'],
                  _bizSize, (v) => setState(() => _bizSize = v),
                  required: true, fieldKey: 'businessSize'),
              _gap(),

              _textField('Person Name *', _personCtrl,
                  icon: Icons.person_outline_rounded,
                  capitalization: TextCapitalization.words,
                  validator: (v) => _validateRequired(v, 'Person name'),
                  fieldKey: 'personName'),
              _gap(),

              _dropdown('Customer Stage *', Icons.flag_rounded,
                  ['Prospect', 'Lead', 'Qualified', 'Opportunity', 'Customer', 'Churned'],
                  _custStage, (v) => setState(() => _custStage = v),
                  required: true, fieldKey: 'customerStage'),
              _gap(),

              _dropdown('Funnel Stage *', Icons.filter_alt_rounded,
                  ['Awareness', 'Interest', 'Consideration', 'Intent', 'Purchase', 'Loyalty'],
                  _funnelStage, (v) => setState(() => _funnelStage = v),
                  required: true, fieldKey: 'funnelStage'),
              _gap(),

              _textField('GST Number', _gstCtrl,
                  icon: Icons.receipt_long_rounded,
                  capitalization: TextCapitalization.characters,
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(15),
                  ],
                  validator: _validateGst,
                  fieldKey: 'gstNumber'),
              _gap(),

              _textField('PAN Card', _panCtrl,
                  icon: Icons.credit_card_rounded,
                  capitalization: TextCapitalization.characters,
                  formatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: _validatePan,
                  fieldKey: 'panCard'),

              const SizedBox(height: 16),

              // ── Images ────────────────────────────────────────────────
              _sectionHeader(Icons.photo_library_rounded, 'Images'),
              const SizedBox(height: 10),
              Row(children: [
                _imageTile('Shop Image', true,  _shopImage),
                const SizedBox(width: 10),
                _imageTile('Shop Owner', false, _ownerImage),
              ]),

              const SizedBox(height: 16),

              // ── Status ────────────────────────────────────────────────
              _sectionHeader(Icons.toggle_on_rounded, 'Status'),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(children: [
                  Icon(_isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: _isActive ? Colors.green : Colors.grey, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Active Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    Text(_isActive ? 'Active' : 'Inactive',
                        style: TextStyle(fontSize: 12, color: _isActive ? Colors.green : Colors.grey)),
                  ])),
                  Switch.adaptive(
                    value: _isActive,
                    activeThumbColor: gold,
                    activeTrackColor: gold.withValues(alpha: 0.4),
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              // ── Location Details ──────────────────────────────────────
              _sectionHeader(Icons.location_on_rounded, 'Location Details'),
              const SizedBox(height: 10),

              Row(children: [
                Expanded(
                  child: _textField('Pincode *', _pincodeCtrl,
                      icon: Icons.pin_drop_outlined,
                      keyboardType: TextInputType.number,
                      formatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      validator: _validatePincode,
                      fieldKey: 'pincode'),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _lookingUpPincode ? null : _lookupPincode,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: Text(_lookingUpPincode ? 'Looking...' : 'Lookup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]),
              _gap(),

              _textField('Country',     _countryCtrl,  icon: Icons.public_rounded,        fieldKey: 'country'),
              _gap(),
              _textField('State',       _stateCtrl,    icon: Icons.map_rounded,            fieldKey: 'state'),
              _gap(),
              _textField('District',    _districtCtrl, icon: Icons.location_city_rounded,  fieldKey: 'district'),
              _gap(),
              _textField('City',        _cityCtrl,     icon: Icons.apartment_rounded,      fieldKey: 'city'),
              _gap(),
              _areaField(),
              _gap(),
              _textField('Full Address', _addressCtrl, icon: Icons.location_on_outlined, fieldKey: 'address'),

              const SizedBox(height: 16),

              // ── Geolocation ───────────────────────────────────────────
              _sectionHeader(Icons.my_location_rounded, 'Geolocation'),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _captureLocation,
                  icon: Icon(_locationCaptured ? Icons.check_circle_rounded : Icons.my_location_rounded, size: 20),
                  label: Text(_locationCaptured ? _locationText : 'Capture Current Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _locationCaptured ? Colors.green : gold,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Submit / Clear ────────────────────────────────────────
              Row(children: [
                Expanded(child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: (_isLoading || _checkingContact) ? null : _submit,
                    icon: (_isLoading || _checkingContact)
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: Text(_isEditMode ? 'Update' : 'Submit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold, foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                )),
                const SizedBox(width: 10),
                Expanded(child: SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : (_isEditMode ? () => context.pop() : _clear),
                    icon: Icon(_isEditMode ? Icons.arrow_back_rounded : Icons.close_rounded, size: 18),
                    label: Text(_isEditMode ? 'Cancel' : 'Clear'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                )),
              ]),

              const SizedBox(height: 20),
            ]),
          ),
        ),

        if (_isLoading)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator(color: gold)),
            ),
          ),
      ]),
    );
  }
}

