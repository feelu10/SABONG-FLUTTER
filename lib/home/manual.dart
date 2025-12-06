import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ManualClaimingPage extends StatefulWidget {
  const ManualClaimingPage({super.key});

  @override
  State<ManualClaimingPage> createState() => _ManualClaimingPageState();
}

class _ManualClaimingPageState extends State<ManualClaimingPage> {
  final TextEditingController _receiptController = TextEditingController();
  bool _isLoading = false;
  String? apiUrl;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('api_url');
    });
    print("📡 Loaded API URL: $apiUrl");
  }

  Future<void> _claimReceipt() async {
    final receiptId = _receiptController.text.trim();

    // Validate input
    if (receiptId.isEmpty || apiUrl == null || !RegExp(r'^\d+$').hasMatch(receiptId)) {
      _showDialog("Invalid Input", "Please enter a valid numeric receipt ID.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? '';
    if (username.isEmpty) {
      _showDialog("No Username", "No username set in app. Please log in again.");
      return;
    }

    setState(() => _isLoading = true);

    final uri = Uri.parse('$apiUrl/api/claim-receipt');
    String title = "Claim Result";
    String message;
    bool success = false;

    try {
      print("📤 Sending POST to: $uri");
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'receipt_id': receiptId,
          'username': username,
        }),
      );

      print("✅ Response status: ${res.statusCode}");
      print("📦 Response body: ${res.body}");

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        title = "Success";
        success = true;
        message = "Claimed: ₱${data['claimed_amount']}\n"
                  "User: ${data['nickname']}\n"
                  "Side: ${data['side'].toString().toUpperCase()}\n"
                  "Status: ${data['status'].toString().toUpperCase()}";
      } else {
        title = "Failed";
        message = data['error'] ?? "Unknown server error.";
      }
    } catch (e) {
      print("❌ Exception: $e");
      title = "Network Error";
      message = "Could not connect to server.";
    }

    if (!mounted) return;

    setState(() => _isLoading = false);

    _showDialog(title, message, success: success);
  }

  void _showDialog(String title, String message, {bool success = false}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (success) _receiptController.clear();
            },
            child: Text(success ? "OK" : "Try Again"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _receiptController,
              autofocus: true,
              textInputAction: TextInputAction.done,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Enter Receipt ID",
                border: OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _receiptController.clear(),
                ),
              ),
              onSubmitted: (_) => !_isLoading ? _claimReceipt() : null,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check_circle),
                label: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text("Claim Now"),
                onPressed: _isLoading ? null : _claimReceipt,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
