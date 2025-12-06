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
  String? qrPath;
  String? teller;
  String? apiUrl;
  String? savedPrinterAddress;
  String? lastPrintError;
  bool _loading = true;
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  BluetoothDevice? selectedPrinter;

  @override
  void initState() {
    super.initState();
    _doAll();
  }

  Future<void> _doAll() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');
    savedPrinterAddress = prefs.getString('printer_address');
    final receipt = widget.bet['receipt_id']?.toString();
    if (apiUrl == null || receipt == null) {
      setState(() {
        lastPrintError = "API URL or receipt missing.";
        _loading = false;
      });
      return;
    }

    // Connect printer ONCE (no disconnect/reconnect in between)
    await _connectPrinterOnce();
    await _fetchTicketData(apiUrl!, receipt);

    if (!mounted) return;
    try {
      await _printTicket(); // Printer is already connected
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Printed successfully!")),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => lastPrintError = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Print failed: $e"), backgroundColor: Colors.red),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _connectPrinterOnce() async {
    bool isConnected = (await bluetooth.isConnected) ?? false;
    if (!isConnected) {
      final devices = await bluetooth.getBondedDevices();
      BluetoothDevice? device;
      if (savedPrinterAddress != null && savedPrinterAddress!.isNotEmpty) {
        device = devices.firstWhere(
          (d) => d.address == savedPrinterAddress,
          orElse: () => BluetoothDevice('', ''),
        );
        if ((device.name ?? '').isEmpty) device = null;
      }
      device ??= devices.firstWhere(
        (d) => (d.name ?? '').toLowerCase().contains('pt'),
        orElse: () => BluetoothDevice('', ''),
      );
      if ((device.name ?? '').isNotEmpty) {
        await bluetooth.connect(device);
      } else {
        throw Exception("PT-210 printer not found!");
      }
    }
  }

  Future<void> _fetchTicketData(String apiUrl, String receipt) async {
    final url = Uri.parse('$apiUrl/api/bet/receipt/$receipt');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() {
        receiptId = data['receipt_id'] ?? receipt;
        fightNumber = data['fight_number']?.toString() ?? widget.bet['fight_number']?.toString() ?? '-';
        qrPath = data['qr_path']?.toString();
        teller = data['teller']?.toString() ?? '';
        _loading = false;
      });
    } else {
      setState(() {
        lastPrintError = "Could not fetch ticket info (404)";
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    bluetooth.disconnect(); // Only disconnect once when page is disposed
    super.dispose();
  }

  Future<void> _printTicket() async {
    setState(() => lastPrintError = null);
    bool isConnected = (await bluetooth.isConnected) ?? false;
    if (!isConnected) throw Exception('Printer not connected!');

    // HEADER
    await bluetooth.printCustom("GAC COCKPIT ARENA", 1, 1);
    await bluetooth.printCustom("OFFICIAL BETTING RECEIPT", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    // INFO
    await bluetooth.printCustom("Fight #: ${fightNumber ?? '-'}", 1, 1);
    await bluetooth.printCustom("Teller: ${teller ?? '-'}", 1, 1);
    await bluetooth.printCustom("Receipt: ${receiptId ?? '-'}", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    // BET LIST
    String side = (widget.bet['side'] ?? '').toString().toUpperCase();
    String amount = widget.bet['amount'] != null ? widget.bet['amount'].toString() : '-';
    await bluetooth.printCustom("${side.padRight(8)}     P${amount.padLeft(5)}", 1, 1);
    await bluetooth.printCustom("--------------------------------", 1, 1);

    // TIME
    await bluetooth.printCustom("Printed: ${_friendlyNow()}", 1, 1);

    // QR CODE (always ensure /static/ prefix)
    if (qrPath != null && apiUrl != null) {
      String path = qrPath!;
      if (!path.startsWith('/static')) {
        if (path.startsWith('/')) {
          path = '/static$path';
        } else {
          path = '/static/$path';
        }
      }
      String fullUrl = apiUrl!;
      if (fullUrl.endsWith('/')) fullUrl = fullUrl.substring(0, fullUrl.length - 1);
      fullUrl = '$fullUrl$path';

      try {
        final qrResponse = await http.get(Uri.parse(fullUrl));
        if (qrResponse.statusCode == 200) {
          Uint8List imageBytes = qrResponse.bodyBytes;
          img.Image? original = img.decodeImage(imageBytes);
          if (original != null) {
            img.Image resized = img.copyResize(original, width: 250, height: 250); // Use smallest readable size
            Uint8List bigBytes = Uint8List.fromList(img.encodePng(resized));
            bool isPrinterStillConnected = (await bluetooth.isConnected) ?? false;
            if (isPrinterStillConnected) {
              await bluetooth.printImageBytes(bigBytes);
              await bluetooth.printNewLine();
            }
          } else {
            await bluetooth.printCustom("[QR Decode Failed]", 1, 1);
          }
        } else {
          await bluetooth.printCustom("[QR Not Found]", 1, 1);
        }
      } catch (e) {
        await bluetooth.printCustom("[QR Print Error]", 1, 1);
      }
    }

    await bluetooth.printNewLine();
    await bluetooth.printNewLine();
  }

  String _friendlyNow() {
    final now = DateTime.now();
    final formatter = DateFormat('MMMM d, y • h:mm a');
    return formatter.format(now);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: _loading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text('Reprinting ticket...\nPlease wait.',
                      textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                ],
              )
            : lastPrintError != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error, color: Colors.red, size: 36),
                      const SizedBox(height: 16),
                      Text(
                        "Print Error: $lastPrintError",
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  )
                : const SizedBox(),
      ),
    );
  }
}
