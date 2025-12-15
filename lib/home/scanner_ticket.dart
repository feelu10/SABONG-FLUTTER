import 'dart:async';
import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ScannerTicketPrintPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String apiUrl;

  const ScannerTicketPrintPage({
    super.key,
    required this.data,
    required this.apiUrl,
  });

  @override
  State<ScannerTicketPrintPage> createState() => _ScannerTicketPrintPageState();
}

class _ScannerTicketPrintPageState extends State<ScannerTicketPrintPage> {
  final BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  String? savedPrinterAddress;
  String? lastPrintError;

  @override
  void initState() {
    super.initState();
    _startPrint();
  }

  // ----------------------------------------------------------
  // MAIN FLOW
  // ----------------------------------------------------------
  Future<void> _startPrint() async {
    try {
      await _loadSavedPrinter();
      await _connectPrinterFast();  // ensure connected
      await _printReceipt();        // print ticket

      if (mounted) Navigator.pop(context);

    } catch (e) {
      setState(() => lastPrintError = e.toString());
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    savedPrinterAddress = prefs.getString('printer_address');
  }

  // ----------------------------------------------------------
  // ⚡ FAST BLUETOOTH CONNECT
  // ----------------------------------------------------------
  Future<void> _connectPrinterFast() async {
    bool connected = (await bluetooth.isConnected) ?? false;
    if (connected) return;

    final List<BluetoothDevice> devices = await bluetooth.getBondedDevices();
    if (devices.isEmpty) throw Exception("No paired printers found.");

    // 1️⃣ Try saved printer
    if (savedPrinterAddress != null) {
      final dev = devices.firstWhere(
        (d) => d.address == savedPrinterAddress,
        orElse: () => BluetoothDevice("", ""),
      );

      if ((dev.name ?? "").isNotEmpty) {
        await bluetooth.connect(dev);
        return;
      }
    }

    // 2️⃣ Try common printer names
    for (var dev in devices) {
      final name = (dev.name ?? "").toLowerCase();
      if (name.contains("pt") || name.contains("printer") || name.contains("thermal")) {
        await bluetooth.connect(dev);

        // Save this automatically
        final prefs = await SharedPreferences.getInstance();
        prefs.setString("printer_address", dev.address ?? "");
        return;
      }
    }

    // 3️⃣ Fallback — connect first paired device
    await bluetooth.connect(devices.first);
  }

  // ----------------------------------------------------------
  // PRINT CLAIMED RECEIPT
  // ----------------------------------------------------------
  Future<void> _printReceipt() async {
    bool connected = (await bluetooth.isConnected) ?? false;
    if (!connected) throw Exception("Printer not connected.");

    final d = widget.data;

    final amount = d['claimed_amount'] ?? 0;
    final nickname = d['nickname'] ?? '-';
    final claimer = d['claimer_nickname'] ?? '-';
    final side = (d['side'] ?? '-').toString().toUpperCase();
    final receipt = d['receipt_id'] ?? '-';
    final fight = d['fight_id']?.toString() ?? '-';
    final eventNameRaw = (d['event_name'] ?? '').toString().trim();

    final now = DateFormat('y-MM-dd h:mm a').format(DateTime.now());

    // ------------------------------
    // FORMAT EVENT NAME (58mm wrap)
    // ------------------------------
    String eventName = eventNameRaw;
    List<String> eventLines = [];

    while (eventName.length > 25) {
      eventLines.add(eventName.substring(0, 25));
      eventName = eventName.substring(25);
    }
    if (eventName.isNotEmpty) eventLines.add(eventName);

    await bluetooth.printNewLine();
    await bluetooth.printCustom("CLAIMED RECEIPT", 2, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    if (eventLines.length == 1) {
      await bluetooth.printCustom("EVENT: ${eventLines[0]}", 1, 0);
    } else {
      await bluetooth.printCustom("EVENT:", 1, 0);
      for (String line in eventLines) {
        await bluetooth.printCustom("  $line", 1, 0);
      }
    }

    await bluetooth.printCustom("RECEIPT: $receipt", 1, 0);
    await bluetooth.printCustom("FIGHT #: $fight", 1, 0);
    await bluetooth.printCustom("BET BY: $nickname", 1, 0);
    await bluetooth.printCustom("CLAIMED BY: $claimer", 1, 0);
    await bluetooth.printCustom("SIDE: $side", 1, 0);
    await bluetooth.printCustom("CLAIMED: P$amount", 1, 0);

    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("Printed: $now", 1, 1);

    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              lastPrintError == null
                  ? "Printing ticket..."
                  : "Print Error: $lastPrintError",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: lastPrintError == null ? Colors.black : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
