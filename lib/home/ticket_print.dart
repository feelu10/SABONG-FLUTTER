import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:image/image.dart' as img;

class TicketPrintPage extends StatefulWidget {
  final List<Map<String, dynamic>> tickets;
  const TicketPrintPage({super.key, required this.tickets});

  @override
  State<TicketPrintPage> createState() => _TicketPrintPageState();
}

class _TicketPrintPageState extends State<TicketPrintPage> {
  String? receiptId = "Processing…";
  String? fightNumber = "Processing…";
  String? eventName = "Processing…";   // ⭐ ADDED
  String? qrPath;
  bool isSubmitting = false;
  bool submitted = false;
  String? apiUrl;
  String? savedPrinterAddress;
  String? lastPrintError;
  String? teller;

  String loaderText = "Connecting to printer…";
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  @override
  void initState() {
    super.initState();
    _initAndPrint();
  }

  // ----------------------------------------------------------
  // MAIN FLOW
  // ----------------------------------------------------------
  Future<void> _initAndPrint() async {
    try {
      setState(() => loaderText = "Loading settings…");
      await _loadApiUrlAndPrinter();

      setState(() => loaderText = "Checking printer status…");
      await _connectWithPing();

      if (!(await bluetooth.isConnected ?? false)) {
        throw Exception("Printer connection failed.");
      }

      setState(() => loaderText = "Submitting ticket…");
      bool ok = await _submitToBackend();
      if (!ok) return _failAndExit("Failed to submit ticket.");

      setState(() => loaderText = "Printing ticket…");
      await _printTicket();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Printed successfully!")),
      );

      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.pop(context);

    } catch (e) {
      _failAndExit(e.toString());
    }
  }

  Future<void> _failAndExit(String msg) async {
    setState(() => lastPrintError = msg);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) Navigator.pop(context);
  }

  // ----------------------------------------------------------
  // LOAD SAVED SETTINGS
  // ----------------------------------------------------------
  Future<void> _loadApiUrlAndPrinter() async {
    final prefs = await SharedPreferences.getInstance();

    apiUrl = prefs.getString('api_url');
    savedPrinterAddress = prefs.getString('printer_address');

    if (savedPrinterAddress == null) {
      throw Exception("No printer selected. Go to Settings → Printer.");
    }
  }

  // ----------------------------------------------------------
  // PING LOGIC
  // ----------------------------------------------------------
  Future<bool> _pingPrinter(BluetoothDevice device) async {
    try {
      await bluetooth.connect(device).timeout(
        const Duration(seconds: 3),
        onTimeout: () => throw Exception("Printer timeout"),
      );

      await bluetooth.disconnect();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ----------------------------------------------------------
  // CONNECT WITH PING
  // ----------------------------------------------------------
  Future<void> _connectWithPing() async {
    bool connected = (await bluetooth.isConnected) ?? false;
    if (connected) return;

    final bonded = await bluetooth.getBondedDevices();
    final matched = bonded.firstWhere(
      (d) => d.address == savedPrinterAddress,
      orElse: () => BluetoothDevice('', ''),
    );

    if ((matched.address ?? "").isEmpty) {
      throw Exception("Saved printer not found.");
    }


    bool alive = await _pingPrinter(matched);
    if (!alive) {
      throw Exception("Printer is OFF or unreachable.");
    }

    try {
      await bluetooth.connect(matched);
    } catch (_) {
      throw Exception("Could not connect to printer: ${matched.name}");
    }
  }

  // ----------------------------------------------------------
  // SUBMIT BET — RECEIVE EVENT NAME
  // ----------------------------------------------------------
  Future<bool> _submitToBackend() async {
    if (isSubmitting || apiUrl == null || submitted) return false;

    setState(() => isSubmitting = true);

    try {
      final t = widget.tickets[0];
      final prefs = await SharedPreferences.getInstance();

      final res = await http.post(
        Uri.parse('$apiUrl/api/bet'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fight_id': t['fight_id'],
          'user': prefs.getString('username') ?? 'teller',
          'side': t['side'],
          'amount': t['amount'],
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        receiptId = data['receipt_id']?.toString();
        qrPath = data['qr_path'];
        teller = prefs.getString('username') ?? "";
        fightNumber = t['fight_number']?.toString();

        // ⭐ EVENT NAME
        eventName = data['event_name']?.toString() ?? "Event";

        submitted = true;
        return true;
      }

      return false;

    } catch (_) {
      return false;
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  // ----------------------------------------------------------
  // PRINT TICKET (SAFE, NO OVERFLOW)
  // ----------------------------------------------------------
  Future<void> _printTicket() async {
    if (!((await bluetooth.isConnected) ?? false)) {
      throw Exception("Printer disconnected.");
    }

    // Force ASCII code page (fixes Chinese-like symbols)
    await bluetooth.writeBytes(Uint8List.fromList([27, 116, 0])); // ESC t 0

    await bluetooth.printCustom("OFFICIAL BETTING RECEIPT", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    // Event safe name
    final safeEvent = (eventName ?? "").length > 25
        ? eventName!.substring(0, 25)
        : eventName;

    await bluetooth.printCustom("Event: $safeEvent", 1, 0);
    await bluetooth.printCustom("Fight #: $fightNumber", 1, 0);
    await bluetooth.printCustom("Teller: ${teller ?? ''}", 1, 0);
    await bluetooth.printCustom("Receipt: $receiptId", 1, 0);

    await bluetooth.printCustom("--------------------------------", 1, 1);

    // ==============================
    //  SAFE TICKET PRINT LOOP
    // ==============================
    for (var t in widget.tickets) {
      String side = t['side'].toString().toUpperCase();
      String amount = t['amount'].toString();

      // Force ASCII before printing every line (super safe)
      await bluetooth.writeBytes(Uint8List.fromList([27, 116, 0]));

      // NOTE: Using PHP instead of ₱ to avoid Unicode issues
      await bluetooth.printCustom("$side   PHP $amount", 1, 0);
    }

    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("${_friendlyNow()}", 1, 0);

    await _printQrCode();

    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
  }

  // ----------------------------------------------------------
  // PRINT QR
  // ----------------------------------------------------------
  Future<void> _printQrCode() async {
    if (qrPath == null || apiUrl == null) return;

    final url = qrPath!.startsWith("/")
        ? "$apiUrl$qrPath"
        : "$apiUrl/$qrPath";

    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) return;

      img.Image? qr = img.decodeImage(res.bodyBytes);
      if (qr == null) return;

      img.Image resized = img.copyResize(qr, width: 250);
      Uint8List png = Uint8List.fromList(img.encodePng(resized));

      if ((await bluetooth.isConnected) ?? false) {
        await bluetooth.printImageBytes(png);
        await bluetooth.printNewLine();
        await bluetooth.printNewLine();
      }
    } catch (_) {}
  }

  String _friendlyNow() {
    return DateFormat('MMMM d, y • h:mm a').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              loaderText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (lastPrintError != null)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  "Error: $lastPrintError",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
