import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ClaimerTakeRatePage extends StatefulWidget {
  const ClaimerTakeRatePage({super.key});

  @override
  State<ClaimerTakeRatePage> createState() => _ClaimerTakeRatePageState();
}

class _ClaimerTakeRatePageState extends State<ClaimerTakeRatePage> {
  double? takeRate;
  bool loading = true;
  String? error;
  bool updating = false;

  @override
  void initState() {
    super.initState();
    _fetchTakeRate();
  }

  Future<void> _fetchTakeRate() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      if (apiUrl == null) {
        setState(() {
          loading = false;
          error = "API URL not set.";
        });
        return;
      }
      final res = await http.get(Uri.parse('$apiUrl/api/take-rate'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          takeRate = (data['rate'] as num?)?.toDouble() ?? 7.5;
          loading = false;
        });
      } else {
        setState(() {
          error = "Failed to fetch rate.";
          loading = false;
        });
      }
    } catch (e) {
      setState(() {
        error = "Network error: $e";
        loading = false;
      });
    }
  }

  Future<void> _showSetRateDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Set Take Rate"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Take Rate (%)",
            hintText: "Enter new rate",
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null) {
                Navigator.of(ctx).pop(val);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
    if (result != null) _setTakeRate(result);
  }

  Future<void> _setTakeRate(double rate) async {
    setState(() => updating = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      if (apiUrl == null) return;
      final res = await http.post(
        Uri.parse('$apiUrl/api/take-rate'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rate': rate}),
      );
      if (res.statusCode == 200) {
        setState(() {
          takeRate = rate;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Take Rate updated!")),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed: ${res.body}"), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Take Rate'),
        backgroundColor: Colors.black87,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(child: Text(error!, style: const TextStyle(color: Colors.red)))
              : Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.percent, size: 60, color: Colors.amber[700]),
                      const SizedBox(height: 24),
                      const Text(
                        "Your Current Take Rate",
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        takeRate == null ? "--" : "${takeRate!.toStringAsFixed(2)}%",
                        style: const TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "The take rate is the percentage you receive per valid claim.\nThis value is updated by the administrator.",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 15, color: Colors.black54),
                      ),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: 180,
                        child: ElevatedButton.icon(
                          icon: updating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.edit),
                          label: Text(takeRate == null ? "Set Rate" : "Update Rate"),
                          onPressed: updating ? null : _showSetRateDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            textStyle: const TextStyle(fontWeight: FontWeight.bold),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
