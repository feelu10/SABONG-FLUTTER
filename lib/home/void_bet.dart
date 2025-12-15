import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:intl/intl.dart';

// =========================================================
//                 VOID BET SCANNER PAGE
// =========================================================

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

          // Center scanning frame
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

// =========================================================
//           VOIDED TICKET PRINT PAGE (FULL FIX)
// =========================================================

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
      await _loadSavedPrinter();

      if (savedPrinterAddress == null) {
        throw Exception("No printer selected. Set printer in Settings.");
      }

      await _connectPrinterFast();      // saved-only connect
      await _printVoidSlip();           // print slip

      if (mounted) Navigator.pop(context);

    } catch (e) {
      setState(() => lastPrintError = e.toString());
    }
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    savedPrinterAddress = prefs.getString('printer_address');
  }

  // ---------------------------------------------------------
  //        SUPER FAST PRINTER CONNECT (STRICT SAVED)
  // ---------------------------------------------------------
  Future<void> _connectPrinterFast() async {
    bool connected = (await bluetooth.isConnected) ?? false;
    if (connected) return;

    final devices = await bluetooth.getBondedDevices();
    if (devices.isEmpty) {
      throw Exception("No paired Bluetooth printers found.");
    }

    final dev = devices.firstWhere(
      (d) => d.address == savedPrinterAddress,
      orElse: () => BluetoothDevice("", ""),
    );

    if ((dev.name ?? "").isEmpty) {
      throw Exception("Saved printer not found. Set printer in Settings.");
    }

    await bluetooth.connect(dev);

    bool ok = (await bluetooth.isConnected) ?? false;
    if (!ok) throw Exception("Failed to connect to saved printer.");
  }

  @override
  void dispose() {
    // Keep connection for instant next print
    super.dispose();
  }

  // ---------------------------------------------------------
  //                   PRINT VOIDED SLIP
  // ---------------------------------------------------------
  Future<void> _printVoidSlip() async {
    final t = widget.ticket;
    final now = DateFormat('y-MM-dd h:mm a').format(DateTime.now());

    if (!((await bluetooth.isConnected) ?? false)) {
      throw Exception("Printer not connected.");
    }

    // ---------- FORMAT EVENT NAME FOR 58mm PAPER ----------
    String eventName = (t['event_name'] ?? '').toString().trim();

    // MAX 25 CHAR PER LINE
    List<String> eventLines = [];
    while (eventName.length > 25) {
      eventLines.add(eventName.substring(0, 25));
      eventName = eventName.substring(25);
    }
    if (eventName.isNotEmpty) eventLines.add(eventName);

    await bluetooth.printNewLine();
    await bluetooth.printCustom("VOIDED BET SLIP", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    // ⭐ IF only one line → print as "EVENT: Name"
    if (eventLines.length == 1) {
      await bluetooth.printCustom("EVENT: ${eventLines[0]}", 1, 0);
    } else {
      // ⭐ MULTI-LINE EVENT
      await bluetooth.printCustom("EVENT:", 1, 0);
      for (String line in eventLines) {
        await bluetooth.printCustom("  $line", 1, 0);
      }
    }

    await bluetooth.printCustom("RECEIPT: ${t['receipt_id']}", 1, 0);
    await bluetooth.printCustom("FIGHT #: ${t['fight_number']}", 1, 0);
    await bluetooth.printCustom("SIDE: ${(t['side'] ?? '-').toString().toUpperCase()}", 1, 0);
    await bluetooth.printCustom("AMOUNT: PHP ${t['amount']}", 1, 0);
    await bluetooth.printCustom("TELLER: ${t['teller']}", 1, 0);
    await bluetooth.printCustom("DATE: ${t['date'] ?? now}", 1, 0);

    await bluetooth.printCustom("--------------------------------", 1, 1);

    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Voided Ticket"),
        backgroundColor: Colors.red[900],
      ),
      body: Center(
        child: lastPrintError == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Printing voided ticket...",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.red, size: 40),
                  const SizedBox(height: 10),
                  Text(
                    "BET VOIDED",
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),

                  const Divider(height: 24),

                  Text("Receipt #: ${t['receipt_id']}"),
                  if (t['fight_number'] != null) Text("Fight #: ${t['fight_number']}"),
                  if (t['side'] != null) Text("Side: ${t['side']}".toUpperCase()),
                  if (t['amount'] != null) Text("Amount: ₱${t['amount']}"),
                  if (t['teller'] != null) Text("Teller: ${t['teller']}"),
                  if (t['date'] != null && t['date'] != "") Text("Date: ${t['date']}"),

                  const SizedBox(height: 20),
                  Text(
                    "Printer error:\n$lastPrintError",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Done"),
                  )
                ],
              ),
      ),
    );
  }
}
