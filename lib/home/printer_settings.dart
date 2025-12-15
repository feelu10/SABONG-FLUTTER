import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as FBS;
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as BT;
import 'package:shared_preferences/shared_preferences.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({super.key});

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  final FBS.FlutterBluetoothSerial bluetooth = FBS.FlutterBluetoothSerial.instance;
  final BT.BlueThermalPrinter printer = BT.BlueThermalPrinter.instance;

  List<FBS.BluetoothDevice> devices = [];
  String? savedAddress;
  bool scanning = false;
  bool printerOnline = false;

  // ---------------------------------------------------------
  // SAFE SETSTATE
  // ---------------------------------------------------------
  void safeSetState(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ---------------------------------------------------------
  // Detect possible thermal printer names
  // ---------------------------------------------------------
  bool isPrinter(FBS.BluetoothDevice d) {
    final name = (d.name ?? "").toLowerCase();
    return name.contains("printer") ||
        name.contains("pos") ||
        name.contains("58") ||
        name.contains("mpt") ||
        name.contains("mtp") ||
        name.contains("pt-") ||
        name.contains("goojprt") ||
        name.contains("thermal");
  }

  // ---------------------------------------------------------
  // INIT
  // ---------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadSavedPrinter();
  }

  @override
  void dispose() {
    try {
      bluetooth.cancelDiscovery();
    } catch (_) {}
    super.dispose();
  }

  // ---------------------------------------------------------
  // LOAD SAVED PRINTER
  // ---------------------------------------------------------
  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    savedAddress = prefs.getString("printer_address");
    safeSetState(() {});

    await _scanDevices();
    await _autoConnectSavedPrinter();
  }

  // ---------------------------------------------------------
  // AUTO-CONNECT TO SAVED PRINTER
  // ---------------------------------------------------------
  Future<void> _autoConnectSavedPrinter() async {
    if (savedAddress == null) return;

    final bonded = await bluetooth.getBondedDevices();
    final dev = bonded.firstWhere(
      (d) => d.address == savedAddress,
      orElse: () => FBS.BluetoothDevice(address: "", name: ""),
    );

    if (dev.address.isEmpty) return;

    try {
      await bluetooth.cancelDiscovery().catchError((_) {});
      await printer.disconnect().catchError((_) => null);
      await Future.delayed(const Duration(milliseconds: 250));

      await printer.connect(BT.BluetoothDevice(dev.name ?? "", dev.address));
      printerOnline = true;
    } catch (_) {
      printerOnline = false;
    }

    safeSetState(() {});
  }

  // ---------------------------------------------------------
  // SCAN DEVICES
  // ---------------------------------------------------------
  Future<void> _scanDevices() async {
    scanning = true;
    devices.clear();
    safeSetState(() {});

    final bonded = await bluetooth.getBondedDevices();
    for (var d in bonded) {
      if (isPrinter(d) && !devices.any((x) => x.address == d.address)) {
        devices.add(d);
      }
    }

    try {
      await bluetooth.cancelDiscovery();
    } catch (_) {}

    final stream = bluetooth.startDiscovery();

    stream.listen((result) {
      final d = result.device;
      if (isPrinter(d) && !devices.any((x) => x.address == d.address)) {
        devices.add(d);
        safeSetState(() {});
      }
    }).onDone(() {
      scanning = false;
      safeSetState(() {});
    });
  }

  // ---------------------------------------------------------
  // SAVE PRINTER + CONNECT
  // ---------------------------------------------------------
  Future<void> _savePrinter(FBS.BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("printer_address", device.address);

    savedAddress = device.address;
    safeSetState(() {});

    try {
      await bluetooth.cancelDiscovery().catchError((_) {});
      await printer.disconnect().catchError((_) => null);
      await Future.delayed(const Duration(milliseconds: 250));

      await printer.connect(BT.BluetoothDevice(device.name ?? "", device.address));
      printerOnline = true;
    } catch (_) {
      printerOnline = false;
    }

    safeSetState(() {});
  }

  // ---------------------------------------------------------
  // TEST PRINT
  // ---------------------------------------------------------
  Future<void> _testPrint(FBS.BluetoothDevice d) async {
    try {
      await bluetooth.cancelDiscovery().catchError((_) {});
      await printer.disconnect().catchError((_) => null);
      await Future.delayed(const Duration(milliseconds: 200));

      await printer.connect(BT.BluetoothDevice(d.name ?? "", d.address));

      await printer.printNewLine();
      await printer.printCustom("TEST PRINT SUCCESS", 2, 1);
      await printer.printCustom("Printer Connected OK", 1, 1);
      await printer.printNewLine();
      await printer.printNewLine();
    } catch (_) {}
  }

  // ---------------------------------------------------------
  // UI
  // ---------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Select Printer"),
        backgroundColor: Colors.red,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _scanDevices),
        ],
      ),
      body: Column(
        children: [
          if (scanning)
            Container(
              padding: const EdgeInsets.only(top: 50, bottom: 20),
              child: Column(
                children: const [
                  CircularProgressIndicator(color: Colors.red, strokeWidth: 3),
                  SizedBox(height: 20),
                  Text("Searching for printers…",
                      style: TextStyle(color: Colors.white, fontSize: 16)),
                  SizedBox(height: 5),
                  Text("Make sure your printer is ON",
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          Expanded(
            child: devices.isEmpty && !scanning
                ? const Center(
                    child: Text(
                      "No printers found.\nTurn printer ON.",
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: devices.length,
                    itemBuilder: (context, i) {
                      final d = devices[i];
                      final isSelected = savedAddress == d.address;
                      final showTest = isSelected && printerOnline;

                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        padding: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.green.withOpacity(0.15)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.green : Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: ListTile(
                                leading: Icon(
                                  Icons.print,
                                  color: isSelected
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
                                  size: 28,
                                ),
                                title: Text(
                                  d.name ?? "Unknown Printer",
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                ),
                                subtitle: Text(
                                  d.address,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        showTest ? Icons.check_circle : Icons.error,
                                        color: showTest ? Colors.green : Colors.red,
                                        size: 26,
                                      )
                                    : null,
                                onTap: () => _savePrinter(d),
                              ),
                            ),
                            if (showTest)
                              ElevatedButton(
                                onPressed: () => _testPrint(d),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                child: const Text("Test", style: TextStyle(fontSize: 13)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
