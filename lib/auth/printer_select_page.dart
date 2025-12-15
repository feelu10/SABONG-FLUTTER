import 'package:flutter/material.dart';
import 'printer_manager.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as FBS;

class PrinterSelectPage extends StatefulWidget {
  const PrinterSelectPage({super.key});

  @override
  State<PrinterSelectPage> createState() => _PrinterSelectPageState();
}

class _PrinterSelectPageState extends State<PrinterSelectPage> {
  bool loading = true;
  List<FBS.BluetoothDiscoveryResult> devices = [];

  @override
  void initState() {
    super.initState();
    loadDevices();
  }

  void loadDevices() async {
    devices = await PrinterManager.discover();
    setState(() => loading = false);
  }

  void selectPrinter(FBS.BluetoothDevice dev) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Pairing… please wait")),
    );

    bool ok = await PrinterManager.pairAndConnect(dev);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Connected to ${dev.name}")),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to connect")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Select Printer")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: devices
                  .map(
                    (r) => ListTile(
                      title: Text(r.device.name ?? "Unknown Printer"),
                      subtitle: Text(r.device.address),
                      trailing: const Icon(Icons.print),
                      onTap: () => selectPrinter(r.device),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}
