import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:image/image.dart' as img;

class TicketReprintPage extends StatefulWidget {
  final Map<String, dynamic> bet;
  const TicketReprintPage({super.key, required this.bet});

  @override
  State<TicketReprintPage> createState() => _TicketReprintPageState();
}

class _TicketReprintPageState extends State<TicketReprintPage> {
  String? receiptId;
  String? fightNumber;
  String? eventName;          // ⭐ EVENT NAME
  String? qrPath;
  String? teller;
  String? apiUrl;

  String? savedPrinterAddress;
  String? lastPrintError;
  bool _loading = true;

  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;

  @override
  void initState() {
    super.initState();
    _doAll();
  }

  // ---------------------------------------------------------
  // MAIN FLOW
  // ---------------------------------------------------------
  Future<void> _doAll() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');
    savedPrinterAddress = prefs.getString('printer_address');

    final receipt = widget.bet['receipt_id']?.toString();

    if (apiUrl == null || receipt == null) {
      setState(() {
        lastPrintError = "Missing API URL or receipt number.";
        _loading = false;
      });
      return;
    }

    if (savedPrinterAddress == null) {
      setState(() {
        lastPrintError = "No printer selected. Set printer in Settings.";
        _loading = false;
      });
      return;
    }

    try {
      // 🚀 FAST re-connect to saved printer
      await _connectPrinterFast();

      // Fetch ticket details (with event name)
      await _fetchTicketData(apiUrl!, receipt);

      if (!mounted) return;

      // Print ticket
      await _printTicket();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ticket reprinted successfully!")),
      );

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);

    } catch (e) {
      setState(() => lastPrintError = e.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Print failed: $e"), backgroundColor: Colors.red),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------
  // 🚀 DIRECT FAST CONNECT TO SAVED PRINTER
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

  // ---------------------------------------------------------
  // FETCH RECEIPT DATA (WITH EVENT NAME)
  // ---------------------------------------------------------
  Future<void> _fetchTicketData(String apiUrl, String receipt) async {
    final res = await http.get(Uri.parse('$apiUrl/api/bet/receipt/$receipt'));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);

      setState(() {
        receiptId = data['receipt_id'] ?? receipt;

        fightNumber = data['fight_number']?.toString()
            ?? widget.bet['fight_number']?.toString()
            ?? '-';

        eventName = data['event_name']?.toString() ?? "Event";   // ⭐ ADDED

        qrPath = data['qr_path']?.toString();
        teller = data['teller']?.toString() ?? '';
        _loading = false;
      });
    } else {
      throw Exception("Unable to fetch ticket data.");
    }
  }

  String cleanAmount(dynamic value) {
    if (value == null) return "-";

    try {
      double n = double.parse(value.toString());
      if (n == n.roundToDouble()) {
        return n.toInt().toString(); 
      } else {
        return n.toString();
      }
    } catch (_) {
      return value.toString();
    }
  }

  Future<void> _printTicket() async {
    bool ok = (await bluetooth.isConnected) ?? false;
    if (!ok) throw Exception("Printer not connected.");

    // Force ASCII
    await bluetooth.writeBytes(Uint8List.fromList([27, 116, 0]));

    await bluetooth.printCustom("OFFICIAL BETTING RECEIPT", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    final safeEvent = (eventName ?? "").length > 25
        ? eventName!.substring(0, 25)
        : eventName ?? '';

    await bluetooth.printCustom("Event: $safeEvent", 1, 0);
    await bluetooth.printCustom("Fight #: ${fightNumber ?? '-'}", 1, 0);
    await bluetooth.printCustom("Teller: ${teller ?? '-'}", 1, 0);
    await bluetooth.printCustom("Receipt: ${receiptId ?? '-'}", 1, 0);

    await bluetooth.printCustom("--------------------------------", 1, 1);

    // CLEANED AMOUNT (NO .0 EVER)
    String side = (widget.bet['side'] ?? '').toString().toUpperCase();
    String amount = cleanAmount(widget.bet['amount']);

    await bluetooth.writeBytes(Uint8List.fromList([27, 116, 0]));
    await bluetooth.printCustom("$side   PHP $amount", 1, 0);

    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("${_friendlyNow()}", 1, 0);

    await _printQrCode();

    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
  }

  // ---------------------------------------------------------
  // PRINT QR CODE
  // ---------------------------------------------------------
  Future<void> _printQrCode() async {
    if (qrPath == null || apiUrl == null) return;

    String p = qrPath!.replaceAll("\\", "/");
    String fileName = p.contains("/") ? p.split("/").last : p;

    String fullUrl = "$apiUrl/static/qr/$fileName";

    try {
      final qrRes = await http.get(Uri.parse(fullUrl));
      if (qrRes.statusCode != 200) return;

      Uint8List bytes = qrRes.bodyBytes;
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      final resized = img.copyResize(decoded, width: 250);
      final png = Uint8List.fromList(img.encodePng(resized));

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

  // ---------------------------------------------------------
  // UI LOADING + ERROR DISPLAY
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text(
                    "Reprinting ticket...\nPlease wait.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : lastPrintError != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.error, color: Colors.red, size: 36),
                      SizedBox(height: 16),
                      Text(
                        "Print Error:\n$lastPrintError",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )
                : const SizedBox(),
      ),
    );
  }
}
