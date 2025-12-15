import 'dart:async';
import 'package:flutter/material.dart';
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ScannerTicketPrintPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String apiUrl;

  const ScannerTicketPrintPage({super.key, required this.data, required this.apiUrl});

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
    _doAll();
  }

  Future<void> _doAll() async {
    print('[PRINTER] Attempt printer reconnect...');
    await _getSavedPrinterAddress();
    await Future.delayed(const Duration(milliseconds: 200));
    await _tryReconnectToSavedPrinter();
    try {
      print('[PRINTER] Printing receipt...');
      final tStart = DateTime.now().millisecondsSinceEpoch;
      await _printReceipt();
      final tEnd = DateTime.now().millisecondsSinceEpoch;
      print('[PRINTER] Printing took ${(tEnd - tStart) / 1000.0} seconds.');
      print('[PRINTER] Print completed OK.');
      setState(() => lastPrintError = null);
      if (mounted) Navigator.of(context).pop(); // Instantly pop after printing
    } catch (e) {
      print('[PRINTER] Print error: $e');
      setState(() => lastPrintError = e.toString());
      if (mounted) Navigator.of(context).pop();
    } finally {
      try {
        print('[PRINTER] Disconnecting printer...');
        await bluetooth.disconnect();
      } catch (_) {}
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
    // 1. Try to use the saved address first.
    if (savedPrinterAddress != null && savedPrinterAddress!.isNotEmpty) {
      device = devices.firstWhere(
        (d) => d.address == savedPrinterAddress,
        orElse: () => BluetoothDevice('', ''),
      );
      if ((device.name ?? '').isEmpty) device = null;
    }
    // 2. Fallback to a device with 'pt' in the name.
    device ??= devices.firstWhere(
      (d) => (d.name ?? '').toLowerCase().contains('pt'),
      orElse: () => BluetoothDevice('', ''),
    );
    if ((device.name ?? '').isEmpty) {
      throw Exception("PT-210 printer not found!");
    }
    print('[PRINTER] Connecting to printer: ${device.name} (${device.address})');
    await bluetooth.connect(device);
    await Future.delayed(const Duration(milliseconds: 300));
    print('[PRINTER] Printer connected.');
  }

  Future<void> _printReceipt() async {
    final d = widget.data;
    final amount = d['claimed_amount'] ?? 0;
    final nickname = d['nickname'] ?? '-';
    final claimer = d['claimer_nickname'] ?? '-';
    final side = (d['side'] ?? '-').toString().toUpperCase();
    final receipt = d['receipt_id'] ?? '-';
    final fight = d['fight_id']?.toString() ?? '-';
    final now = DateFormat('y-MM-dd h:mm a').format(DateTime.now());

    bool isConnected = (await bluetooth.isConnected) ?? false;
    if (!isConnected) throw Exception("Printer not connected.");

    await bluetooth.printNewLine();
    await bluetooth.printCustom("GAC COCKPIT ARENA", 1, 1);
    await bluetooth.printCustom("CLAIMED RECEIPT", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("RECEIPT: $receipt", 1, 1);
    await bluetooth.printCustom("FIGHT #: $fight", 1, 1);
    await bluetooth.printCustom("BET BY: $nickname", 1, 1);
    await bluetooth.printCustom("CLAIMED BY: $claimer", 1, 1);
    await bluetooth.printCustom("SIDE: $side", 1, 1);
    await bluetooth.printCustom("CLAIMED: P${amount.toString()}", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);
    await bluetooth.printCustom("Printed: $now", 1, 1);
    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
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
              lastPrintError == null
                  ? 'Printing Claimed Ticket...'
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
