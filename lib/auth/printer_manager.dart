import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as FBS;
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as BT;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class PrinterManager {
  static final bt = FBS.FlutterBluetoothSerial.instance;
  static final thermal = BT.BlueThermalPrinter.instance;

  // ============================================================
  //                    RUNTIME PERMISSIONS
  // ============================================================
  static Future<bool> requestPermissions() async {
    // Request ALL permissions needed for Bluetooth scanning + connection
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
      Permission.locationWhenInUse,
    ].request();

    bool okScan = await Permission.bluetoothScan.isGranted;
    bool okConnect = await Permission.bluetoothConnect.isGranted;

    // Location MUST be granted or scanning will throw PlatformException
    bool okLocation =
        await Permission.location.isGranted ||
        await Permission.locationWhenInUse.isGranted;

    if (!okScan || !okConnect || !okLocation) {
      print("❌ Missing required Bluetooth or Location permissions");
      return false;
    }

    print("✅ Permissions granted");
    return true;
  }

  // ============================================================
  //                    DISCOVER DEVICES
  // ============================================================
  static Future<List<FBS.BluetoothDiscoveryResult>> discover() async {
    bool ok = await requestPermissions();
    if (!ok) return [];

    final List<FBS.BluetoothDiscoveryResult> results = [];

    try {
      print("🔍 Starting Bluetooth discovery...");
      var stream = bt.startDiscovery();

      stream.listen((r) {
        results.add(r);
      });

      // Give some time for discovery
      await Future.delayed(const Duration(seconds: 3));
      await bt.cancelDiscovery();

      print("✅ Discovery complete. Found ${results.length} devices.");
    } catch (e) {
      print("❌ Discovery error: $e");
    }

    return results;
  }

  // ============================================================
  //               PAIR + CONNECT TO PRINTER
  // ============================================================
  static Future<bool> pairAndConnect(FBS.BluetoothDevice dev) async {
    try {
      bool ok = await requestPermissions();
      if (!ok) return false;

      bool bonded = dev.isBonded == true;

      if (!bonded) {
        print("🔗 Pairing with device...");
        final result = await bt.bondDeviceAtAddress(dev.address);
        bonded = result == true;
      }

      if (!bonded) {
        print("❌ Pairing failed");
        return false;
      }

      print("🔌 Connecting to printer...");
      await thermal.connect(
        BT.BluetoothDevice(dev.name ?? "", dev.address),
      );

      final prefs = await SharedPreferences.getInstance();
      prefs.setString("printer_address", dev.address);

      print("✅ Printer saved + connected!");
      return true;

    } catch (e) {
      print("❌ Pair/Connect error: $e");
      return false;
    }
  }

  // ============================================================
  //                      AUTO CONNECT
  // ============================================================
  static Future<bool> autoConnect() async {
    bool ok = await requestPermissions();
    if (!ok) return false;

    final prefs = await SharedPreferences.getInstance();
    String? saved = prefs.getString("printer_address");
    if (saved == null) return false;

    List<FBS.BluetoothDevice> bonded = await bt.getBondedDevices();

    for (var dev in bonded) {
      if (dev.address == saved) {
        try {
          print("🔌 Auto-connecting to saved printer...");
          await thermal.connect(
            BT.BluetoothDevice(dev.name ?? "", dev.address),
          );
          print("✅ Auto-connect success");
          return true;
        } catch (_) {}
      }
    }

    print("❌ Auto-connect failed: Saved printer not found");
    return false;
  }
}
