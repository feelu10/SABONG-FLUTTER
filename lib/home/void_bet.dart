import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:intl/intl.dart';

class VoidBetPage extends StatefulWidget {
  const VoidBetPage({Key? key}) : super(key: key);

  @override
  State<VoidBetPage> createState() => _VoidBetPageState();
}

class _VoidBetPageState extends State<VoidBetPage> {
  bool _scanned = false;
  String? apiUrl;
  String? _username;
  bool _loadingApi = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('api_url');
      _username = prefs.getString('username');
      _loadingApi = false;
    });
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_scanned || _loadingApi || apiUrl == null || _username == null) return;

    final code = capture.barcodes.first.rawValue;
    if (code == null) return;

    setState(() => _scanned = true);

    final receiptId = RegExp(r'\d+').stringMatch(code) ?? code;

    final uri = Uri.parse('$apiUrl/api/bet/void-receipt');
    String title = "Void Result";
    String message = "";
    bool success = false;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'receipt_id': receiptId,
          'username': _username,
        }),
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        title = "Voided";
        success = true;
        message = data['message'] ?? "Bet successfully voided.";
        final ticket = data['ticket'];

        // Print the voiding ticket immediately (no delay)
        if (ticket != null && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VoidTicketPrintPage(ticket: ticket),
            ),
          );
        }
      } else {
        title = "Failed";
        message = data['error'] ?? "Unknown server error.";
      }
    } catch (e) {
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
        onPopInvoked: (didPop) {},
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
      appBar: AppBar(
        title: const Text('Void Bet Scanner'),
        backgroundColor: Colors.red[900],
      ),
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
                'Scan bet receipt QR to void',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
          const Positioned(
            bottom: 36,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Only PENDING bets with OPEN fights can be voided.',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- Instant printer, no artificial delay ----
class VoidTicketPrintPage extends StatefulWidget {
  final Map ticket;
  const VoidTicketPrintPage({super.key, required this.ticket});

  @override
  State<VoidTicketPrintPage> createState() => _VoidTicketPrintPageState();
}

class _VoidTicketPrintPageState extends State<VoidTicketPrintPage> {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  String? savedPrinterAddress;
  String? lastPrintError;

  @override
  void initState() {
    super.initState();
    _printImmediately();
  }

  Future<void> _printImmediately() async {
    try {
      await _getSavedPrinterAddress();
      await _tryReconnectToSavedPrinter();
      await _printVoidTicket();
      if (mounted) Navigator.of(context).pop(); // Pop right after printing!
    } catch (e) {
      setState(() => lastPrintError = e.toString());
    }
  }

  Future<void> _getSavedPrinterAddress() async {
    final prefs = await SharedPreferences.getInstance();
    savedPrinterAddress = prefs.getString('printer_address');
  }

  Future<void> _tryReconnectToSavedPrinter() async {
    bool isConnected = (await bluetooth.isConnected) ?? false;
    if (isConnected) return;
    final devices = await bluetooth.getBondedDevices();

    BluetoothDevice? device;
    // 1. Try saved address
    if (savedPrinterAddress != null && savedPrinterAddress!.isNotEmpty) {
      device = devices.firstWhere(
        (d) => d.address == savedPrinterAddress,
        orElse: () => BluetoothDevice('', ''),
      );
      if ((device.name ?? '').isEmpty) device = null;
    }
    // 2. Fallback to device with 'pt' in the name.
    device ??= devices.firstWhere(
      (d) => (d.name ?? '').toLowerCase().contains('pt'),
      orElse: () => BluetoothDevice('', ''),
    );
    if ((device.name ?? '').isEmpty) {
      throw Exception("PT-210 printer not found!");
    }
    await bluetooth.connect(device);
  }

  Future<void> _printVoidTicket() async {
    final t = widget.ticket;
    final now = DateFormat('y-MM-dd h:mm a').format(DateTime.now());

    bool isConnected = (await bluetooth.isConnected) ?? false;
    if (!isConnected) throw Exception("Printer not connected.");

    await bluetooth.printNewLine();
    await bluetooth.printCustom("GAC COCKPIT ARENA", 1, 1);
    await bluetooth.printCustom("VOIDED BET SLIP", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("RECEIPT: ${t['receipt_id'] ?? '-'}", 1, 1);
    await bluetooth.printCustom("FIGHT #: ${t['fight_number'] ?? '-'}", 1, 1);
    await bluetooth.printCustom("SIDE: ${(t['side'] ?? '-').toString().toUpperCase()}", 1, 1);
    await bluetooth.printCustom("AMOUNT: P${t['amount'] ?? '-'}", 1, 1);
    await bluetooth.printCustom("TELLER: ${t['teller'] ?? '-'}", 1, 1);
    await bluetooth.printCustom("DATE: ${t['date'] ?? now}", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("Printed: $now", 1, 1);
    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voided Ticket'),
        backgroundColor: Colors.red[900],
      ),
      body: Center(
        child: lastPrintError == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 18),
                  Text(
                    'Printing Voided Ticket...',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cancel, color: Colors.red, size: 40),
                  const SizedBox(height: 10),
                  Text("BET VOIDED", style: TextStyle(color: Colors.red[800], fontWeight: FontWeight.bold, fontSize: 20)),
                  const Divider(height: 24, thickness: 2),
                  Text("Receipt #: ${t['receipt_id']}", style: const TextStyle(fontSize: 16)),
                  if (t['fight_number'] != null)
                    Text("Fight #: ${t['fight_number']}"),
                  if (t['side'] != null)
                    Text("Side: ${t['side']}".toUpperCase()),
                  if (t['amount'] != null)
                    Text("Amount: ₱${t['amount']}"),
                  if (t['teller'] != null)
                    Text("Teller: ${t['teller']}"),
                  if (t['date'] != null && t['date'] != "")
                    Text("Date: ${t['date']}"),
                  const SizedBox(height: 15),
                  Text(
                    "Printer error:\n$lastPrintError",
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Done'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
      ),
    );
  }
}
