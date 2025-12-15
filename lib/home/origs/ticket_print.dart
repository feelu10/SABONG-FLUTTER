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
  String? qrPath;
  bool isSubmitting = false;
  bool submitted = false;
  String? apiUrl;
  String? savedPrinterAddress;
  String? lastPrintError;
  String? teller;

  String loaderText = "Connecting to printer…";
  BlueThermalPrinter bluetooth = BlueThermalPrinter.instance;
  BluetoothDevice? selectedPrinter;

  @override
  void initState() {
    super.initState();
    _initAndPrint();
  }

  Future<void> _initAndPrint() async {
    try {
      setState(() => loaderText = "Loading settings…");
      await _getApiUrlAndPrinterAddress();

      setState(() => loaderText = "Connecting to printer…");
      await _connectPrinterOnce();

      setState(() => loaderText = "Submitting ticket…");
      bool ok = await _submitToBackend();
      if (!ok) {
        setState(() => loaderText = "Submission failed.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to submit ticket."), backgroundColor: Colors.red),
        );
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        Navigator.of(context).pop();
        return;
      }

      setState(() => loaderText = "Printing ticket…");
      await _printTicket();

      setState(() => loaderText = "Done!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Printed successfully!")),
      );
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop();

    } catch (e) {
      setState(() {
        loaderText = "Print Error: $e";
        lastPrintError = e.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Print failed: $e"), backgroundColor: Colors.red),
      );
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _getApiUrlAndPrinterAddress() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');
    savedPrinterAddress = prefs.getString('printer_address');
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
        print('[PRINTER] Connecting to: ${device.name} (${device.address})');
        await bluetooth.connect(device);
        print('[PRINTER] Connected!');
      } else {
        print('[PRINTER] No PT printer found!');
        throw Exception('No PT printer found!');
      }
    }
  }

  @override
  void dispose() {
    bluetooth.disconnect(); // Only disconnect ONCE on dispose
    super.dispose();
  }

  Future<bool> _checkUserStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final api = prefs.getString('api_url');

    if (username == null || api == null) return true; // assume safe if missing

    final res = await http.post(
      Uri.parse('$api/api/check-user-status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username}),
    );

    if (res.statusCode == 403 || res.statusCode == 404) {
      final preservedApi = api;
      await prefs.clear();
      await prefs.setString('api_url', preservedApi);

      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Account Issue"),
          content: const Text("Your account is either deactivated or does not exist. You will be logged out."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
              },
              child: const Text("OK"),
            ),
          ],
        ),
      );
      return false;
    }

    return true;
  }

  Future<bool> _submitToBackend() async {
    if (isSubmitting || apiUrl == null || submitted) return false;
    print('[BET] Start _submitToBackend at ${DateTime.now()}');
    final startAll = DateTime.now().millisecondsSinceEpoch;

    bool ok = await _checkUserStatus();
    if (!ok) {
      print('[BET] _checkUserStatus failed at ${DateTime.now()}');
      return false;
    }

    setState(() => isSubmitting = true);

    try {
      final t = widget.tickets[0];
      final fightId = t['fight_id'];
      if (fightId == null) {
        if (!mounted) return false;
        setState(() => isSubmitting = false);
        print('[BET] No fightId at ${DateTime.now()}');
        return false;
      }
      final uri = Uri.parse('$apiUrl/api/bet');
      print('[BET] POST to $uri at ${DateTime.now()}');

      final startPost = DateTime.now().millisecondsSinceEpoch;
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fight_id': fightId,
          'user': (await SharedPreferences.getInstance()).getString('username') ?? 'teller',
          'side': t['side'],
          'amount': t['amount'],
        }),
      );
      final endPost = DateTime.now().millisecondsSinceEpoch;

      print('[BET] API response at ${DateTime.now()}');
      print('[BET] API POST duration: ${(endPost - startPost) / 1000.0} seconds');

      if (!mounted) return false;

      if (res.statusCode == 200) {
        final resp = jsonDecode(res.body);
        setState(() {
          receiptId = resp['receipt_id']?.toString() ?? '-';
          fightNumber = t['fight_number']?.toString() ?? '-';
          qrPath = resp['qr_path']?.toString();
          submitted = true;
          teller = resp['teller']?.toString() ?? '';
        });

        final endAll = DateTime.now().millisecondsSinceEpoch;
        print('[BET] _submitToBackend total duration: ${(endAll - startAll) / 1000.0} seconds');
        return true;
      } else {
        if (!mounted) return false;
        setState(() => receiptId = "Error!");
        print('[BET] API Error status ${res.statusCode} at ${DateTime.now()}');
        return false;
      }
    } catch (e) {
      if (!mounted) return false;
      setState(() => receiptId = "Error!");
      print('[BET] Exception: $e at ${DateTime.now()}');
      return false;
    } finally {
      if (mounted) {
        setState(() => isSubmitting = false);
      }
    }
  }

  Future<void> _printTicket() async {
    setState(() => lastPrintError = null);

    try {
      bool isConnected = (await bluetooth.isConnected) ?? false;
      if (!isConnected) throw Exception('Printer not connected!');

      await bluetooth.printCustom("GAC COCKPIT ARENA", 1, 1);
      await bluetooth.printCustom("OFFICIAL BETTING RECEIPT", 1, 1);
      await bluetooth.printCustom("--------------------------------", 1, 1);

      await bluetooth.printCustom("Fight #: ${fightNumber ?? '-'}", 1, 1);
      await bluetooth.printCustom("Teller: ${teller ?? '-'}", 1, 1);
      await bluetooth.printCustom("Receipt: ${receiptId ?? '-'}", 1, 1);
      await bluetooth.printCustom("--------------------------------", 1, 1);

      for (var t in widget.tickets) {
        String side = (t['side'] ?? '').toString().toUpperCase();
        String amount = t['amount'] != null ? t['amount'].toString() : '-';
        await bluetooth.printCustom("${side.padRight(8)}     P${amount.padLeft(5)}", 1, 1);
      }
      await bluetooth.printCustom("--------------------------------", 1, 1);

      await bluetooth.printCustom("Printed: ${_friendlyNow()}", 1, 1);

      if (qrPath != null && apiUrl != null) {
        String fullUrl = qrPath!.startsWith('/') ? '$apiUrl$qrPath' : '$apiUrl/$qrPath';
        try {
          final qrResponse = await http.get(Uri.parse(fullUrl));
          await Future.delayed(const Duration(milliseconds: 100));
          if (qrResponse.statusCode == 200) {
            Uint8List imageBytes = qrResponse.bodyBytes;
            img.Image? original = img.decodeImage(imageBytes);
            if (original != null) {
              await Future.delayed(const Duration(milliseconds: 100));
              img.Image resized = img.copyResize(original, width: 250, height: 250);
              Uint8List bigBytes = Uint8List.fromList(img.encodePng(resized));
              bool isPrinterStillConnected = (await bluetooth.isConnected) ?? false;
              if (isPrinterStillConnected) {
                await bluetooth.printImageBytes(bigBytes);
                await Future.delayed(const Duration(milliseconds: 100));
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
    } catch (e) {
      setState(() => lastPrintError = e.toString());
      rethrow;
    }
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
            if (lastPrintError != null) ...[
              const SizedBox(height: 20),
              Text(
                "Print Error: $lastPrintError",
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
