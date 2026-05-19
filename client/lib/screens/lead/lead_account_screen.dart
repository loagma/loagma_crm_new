import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class LeadAccountScreen extends StatefulWidget {
  const LeadAccountScreen({super.key});

  @override
  State<LeadAccountScreen> createState() => _LeadAccountScreenState();
}

class _LeadAccountScreenState extends State<LeadAccountScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
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

  // Dropdowns
  String? _bizType;
  String? _bizSize;
  String? _custStage;
  String? _funnelStage;

  // Toggles
  bool _isActive = true;

  // Image placeholders
  String? _shopImage;
  String? _ownerImage;

  // Geolocation
  bool _locationCaptured = false;
  String _locationText = '';

  @override
  void dispose() {
    _contactCtrl.dispose(); _bizNameCtrl.dispose(); _personCtrl.dispose();
    _gstCtrl.dispose(); _panCtrl.dispose(); _pincodeCtrl.dispose();
    _countryCtrl.dispose(); _stateCtrl.dispose(); _districtCtrl.dispose();
    _cityCtrl.dispose(); _areaCtrl.dispose();
    super.dispose();
  }

  void _lookupPincode() {
    final pin = _pincodeCtrl.text.trim();
    if (pin.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid 6-digit pincode')),
      );
      return;
    }
    // TODO: wire to a real pincode API
    setState(() {
      _countryCtrl.text  = 'India';
      _stateCtrl.text    = '';
      _districtCtrl.text = '';
      _cityCtrl.text     = '';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Looking up $pin…')),
    );
  }

  void _captureLocation() {
    // TODO: wire to geolocator package
    setState(() {
      _locationCaptured = true;
      _locationText = 'Location captured';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Location captured')),
    );
  }

  void _pickImage(bool isShop) {
    setState(() {
      if (isShop) {
        _shopImage = 'selected';
      } else {
        _ownerImage = 'selected';
      }
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    // TODO: call API
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Submitting…')),
    );
  }

  void _clear() {
    _formKey.currentState!.reset();
    setState(() {
      _bizType = null; _bizSize = null;
      _custStage = null; _funnelStage = null;
      _isActive = true;
      _shopImage = null; _ownerImage = null;
      _locationCaptured = false; _locationText = '';
    });
    for (final c in [
      _contactCtrl, _bizNameCtrl, _personCtrl, _gstCtrl, _panCtrl,
      _pincodeCtrl, _countryCtrl, _stateCtrl, _districtCtrl, _cityCtrl, _areaCtrl,
    ]) {
      c.clear();
    }
  }

  // ── UI helpers ─────────────────────────────────────────────────────────────

  static const gold = Color(0xFFD7BE69);
  static const goldLight = Color(0xFFFFF8EE);

  OutlineInputBorder _border(Color c) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c));

  InputDecoration _dec(String label, {IconData? icon, String? errorText}) => InputDecoration(
    labelText: label,
    errorText: errorText,
    prefixIcon: icon != null ? Icon(icon, size: 20, color: gold) : null,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    filled: true,
    fillColor: Colors.white,
    border: _border(Colors.grey.shade300),
    enabledBorder: _border(Colors.grey.shade300),
    focusedBorder: _border(gold),
    errorBorder: _border(Colors.red.shade300),
    focusedErrorBorder: _border(Colors.red),
    labelStyle: const TextStyle(color: Colors.grey),
  );

  Widget _sectionHeader(IconData icon, String title) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: goldLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      Icon(icon, size: 18, color: gold),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: gold)),
    ]),
  );

  Widget _gap() => const SizedBox(height: 10);

  Widget _dropdown(String label, IconData icon, List<String> items, String? value, void Function(String?) onChanged, {bool required = false}) =>
      DropdownButtonFormField<String>(
        initialValue: value,
        decoration: _dec(label, icon: icon),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: gold),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14)))).toList(),
        onChanged: onChanged,
        validator: required ? (v) => v == null ? 'Required' : null : null,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
      );

  Widget _imageTile(String label, bool isShop, bool selected) => Expanded(
    child: GestureDetector(
      onTap: () => _pickImage(isShop),
      child: Container(
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: selected ? gold : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(
            selected ? Icons.check_circle_rounded : Icons.add_photo_alternate_rounded,
            size: 30,
            color: selected ? Colors.green : gold,
          ),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
          const SizedBox(height: 2),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.camera_alt_outlined, size: 13, color: Colors.grey),
            SizedBox(width: 4),
            Icon(Icons.folder_outlined, size: 13, color: Colors.grey),
            SizedBox(width: 4),
            Text('Tap to select', style: TextStyle(fontSize: 11, color: Colors.grey)),
          ]),
        ]),
      ),
    ),
  );

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Lead Account'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Business Information ─────────────────────────────────
              _sectionHeader(Icons.business_rounded, 'Business Information'),
              const SizedBox(height: 10),

              TextFormField(
                controller: _contactCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: _dec('Contact Number *', icon: Icons.phone_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _gap(),

              TextFormField(
                controller: _bizNameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _dec('Business Name *', icon: Icons.store_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _gap(),

              _dropdown('Business Type *', Icons.account_tree_rounded,
                  ['Retail', 'Wholesale', 'Manufacturer', 'Service', 'Distributor', 'Other'],
                  _bizType, (v) => setState(() => _bizType = v), required: true),
              _gap(),

              _dropdown('Business Size *', Icons.group_work_rounded,
                  ['Micro', 'Small', 'Medium', 'Large', 'Enterprise'],
                  _bizSize, (v) => setState(() => _bizSize = v), required: true),
              _gap(),

              TextFormField(
                controller: _personCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: _dec('Person Name *', icon: Icons.person_outline_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              _gap(),

              _dropdown('Customer Stage *', Icons.flag_rounded,
                  ['Prospect', 'Lead', 'Qualified', 'Opportunity', 'Customer', 'Churned'],
                  _custStage, (v) => setState(() => _custStage = v), required: true),
              _gap(),

              _dropdown('Funnel Stage *', Icons.filter_alt_rounded,
                  ['Awareness', 'Interest', 'Consideration', 'Intent', 'Purchase', 'Loyalty'],
                  _funnelStage, (v) => setState(() => _funnelStage = v), required: true),
              _gap(),

              TextFormField(
                controller: _gstCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _dec('GST Number', icon: Icons.receipt_long_rounded),
              ),
              _gap(),

              TextFormField(
                controller: _panCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: _dec('PAN Card', icon: Icons.credit_card_rounded),
              ),

              const SizedBox(height: 16),

              // ── Images ───────────────────────────────────────────────
              _sectionHeader(Icons.photo_library_rounded, 'Images'),
              const SizedBox(height: 10),

              Row(children: [
                _imageTile('Shop Image *', true, _shopImage != null),
                const SizedBox(width: 10),
                _imageTile('Shop Owner *', false, _ownerImage != null),
              ]),

              const SizedBox(height: 16),

              // ── Status ───────────────────────────────────────────────
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
                  Icon(
                    _isActive ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: _isActive ? Colors.green : Colors.grey,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Active Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(_isActive ? 'Active' : 'Inactive',
                          style: TextStyle(fontSize: 12, color: _isActive ? Colors.green : Colors.grey)),
                    ],
                  )),
                  Switch.adaptive(
                    value: _isActive,
                    activeThumbColor: gold,
                    activeTrackColor: gold.withValues(alpha: 0.4),
                    onChanged: (v) => setState(() => _isActive = v),
                  ),
                ]),
              ),

              const SizedBox(height: 16),

              // ── Location Details ─────────────────────────────────────
              _sectionHeader(Icons.location_on_rounded, 'Location Details'),
              const SizedBox(height: 10),

              // Pincode + Lookup
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _pincodeCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: _dec('Pincode *', icon: Icons.pin_drop_outlined),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _lookupPincode,
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Lookup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: gold,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]),
              _gap(),

              TextFormField(
                controller: _countryCtrl,
                decoration: _dec('Country', icon: Icons.public_rounded),
              ),
              _gap(),

              TextFormField(
                controller: _stateCtrl,
                decoration: _dec('State', icon: Icons.map_rounded),
              ),
              _gap(),

              TextFormField(
                controller: _districtCtrl,
                decoration: _dec('District', icon: Icons.location_city_rounded),
              ),
              _gap(),

              TextFormField(
                controller: _cityCtrl,
                decoration: _dec('City', icon: Icons.apartment_rounded),
              ),
              _gap(),

              TextFormField(
                controller: _areaCtrl,
                decoration: _dec('Enter Main Area *', icon: Icons.home_rounded),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),

              const SizedBox(height: 16),

              // ── Geolocation ──────────────────────────────────────────
              _sectionHeader(Icons.my_location_rounded, 'Geolocation *'),
              const SizedBox(height: 10),

              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _captureLocation,
                  icon: Icon(
                    _locationCaptured ? Icons.check_circle_rounded : Icons.my_location_rounded,
                    size: 20,
                  ),
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

              // ── Submit / Clear ───────────────────────────────────────
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _submit,
                      icon: const Icon(Icons.save_rounded, size: 18),
                      label: const Text('Submit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
