import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'scanner_ticket.dart'; // Ensure the path is correct

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  bool _scanned = false;
  String? apiUrl;
  bool _loadingApi = true;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('api_url');
      _loadingApi = false;
    });
    // print("📡 Loaded API URL from SharedPreferences: $apiUrl");
    // In production, replace with logging, or just remove
  }

  // Removed unused _getUserBalance

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned || _loadingApi || apiUrl == null) return;

    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    setState(() => _scanned = true);

    final receiptId = RegExp(r'\d+').stringMatch(code) ?? code;
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username') ?? 'unknown';

    final uri = Uri.parse('$apiUrl/api/claim-receipt');
    String title = "Claim Result";
    String message = "";
    bool success = false;
    Map<String, dynamic> data = {};

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // print("📤 Sending POST to: $uri");
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'receipt_id': receiptId,
          'username': username,
        }),
      );

      // print("✅ Response status: ${res.statusCode}");
      // print("📦 Response body: ${res.body}");

      if (!mounted) return;
      Navigator.of(context).pop();

      data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        title = "Success";
        success = true;

        final status = data['status']?.toString().toLowerCase() ?? '';
        final claimedAmount = double.tryParse(data['claimed_amount'].toString()) ?? 0.0;
        final nickname = data['nickname'];
        final claimerNickname = data['claimer_nickname'];
        final side = data['side'];

        message = "Claimed: ₱$claimedAmount\n"
            "Bet by: $nickname\n"
            "Claimed by: $claimerNickname\n"
            "Side: ${side.toString().toUpperCase()}\n"
            "Status: ${status.toUpperCase()}";

        // Always print for win/draw/cancelled, not only win!
        data['receipt_id'] = receiptId;
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScannerTicketPrintPage(
              data: data,
              apiUrl: apiUrl!,
            ),
          ),
        );
      } else {
        title = "Failed";
        message = data['error'] ?? "Unknown server error.";
      }
    } catch (e) {
      // print("❌ Exception occurred: $e");
      if (!mounted) return;
      Navigator.of(context).pop();
      title = "Network Error";
      message = "Could not connect to server.";
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        onPopInvoked: (didPop) {}, // Prevent pop (replacement for WillPopScope)
        child: AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() => _scanned = false);
              },
              child: Text(success ? "Scan Another" : "Try Again"),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingApi) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (apiUrl == null) {
      return const Scaffold(
        body: Center(child: Text('API URL not set.')),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            controller: MobileScannerController(
              detectionSpeed: DetectionSpeed.noDuplicates,
              facing: CameraFacing.back,
            ),
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.redAccent, width: 3),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          const Positioned(
            top: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Align the QR code inside the box',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
