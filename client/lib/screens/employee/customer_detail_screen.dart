import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const CustomerDetailScreen({
    super.key,
    required this.customer,
  });

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _green = Color(0xFF43A047);

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _call(String phone) => _launch('tel:$phone');

  void _whatsapp(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final number = digits.length == 10 ? '91$digits' : digits;
    _launch('https://wa.me/$number');
  }

  @override
  Widget build(BuildContext context) {
    final userid = (widget.customer['userid'] ?? '').toString();
    final name = (widget.customer['shop_name'] as String?)?.isNotEmpty == true
        ? widget.customer['shop_name']
        : (widget.customer['name'] ?? 'Customer');
    final personName = (widget.customer['name'] ?? '').toString();
    final phone = (widget.customer['contactno'] ?? '').toString();
    final email = (widget.customer['email'] ?? '').toString();
    final address = (widget.customer['address'] ?? widget.customer['shop_address'] ?? '').toString();
    final city = (widget.customer['city'] ?? '').toString();
    final state = (widget.customer['state'] ?? '').toString();
    final pincode = (widget.customer['pincode'] ?? '').toString();
    final userType = (widget.customer['user_type'] ?? '').toString();
    final latitude = widget.customer['latitude'];
    final longitude = widget.customer['longitude'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Customer Details'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEEEEE)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Shop/Customer name
                  Text(name,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),

                  // Customer chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade400),
                    ),
                    child: Text(
                      'Customer',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Details rows
                  if (userid.isNotEmpty) ...[
                    _detailRow('User ID:', userid),
                    const SizedBox(height: 8),
                  ],
                  if (personName.isNotEmpty) ...[
                    _detailRow('Owner Name:', personName),
                    const SizedBox(height: 8),
                  ],
                  if (email.isNotEmpty) ...[
                    _detailRow('Email:', email),
                    const SizedBox(height: 8),
                  ],
                  if (phone.isNotEmpty) ...[
                    _detailRow('Phone:', phone),
                    const SizedBox(height: 8),
                  ],
                  if (address.isNotEmpty) ...[
                    _detailRow('Address:', address),
                    const SizedBox(height: 8),
                  ],
                  if (city.isNotEmpty) ...[
                    _detailRow('City:', city),
                    const SizedBox(height: 8),
                  ],
                  if (state.isNotEmpty) ...[
                    _detailRow('State:', state),
                    const SizedBox(height: 8),
                  ],
                  if (pincode.isNotEmpty) ...[
                    _detailRow('Pincode:', pincode),
                    const SizedBox(height: 8),
                  ],
                  if (userType.isNotEmpty) ...[
                    _detailRow('Customer Type:', userType),
                    const SizedBox(height: 8),
                  ],
                  if (latitude != null && latitude != 0) ...[
                    _detailRow('Latitude:', latitude.toString()),
                    const SizedBox(height: 8),
                  ],
                  if (longitude != null && longitude != 0) ...[
                    _detailRow('Longitude:', longitude.toString()),
                  ],

                  const SizedBox(height: 14),

                  // Action buttons
                  Row(
                    children: [
                      if (phone.isNotEmpty) ...[
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _call(phone),
                            icon: const Icon(Icons.call_rounded, size: 16),
                            label: const Text('Call'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () => _whatsapp(phone),
                            icon: const Icon(Icons.chat_rounded, size: 16),
                            label: const Text('WhatsApp'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF25D366),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }
}
