import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DetailsTellerPage extends StatefulWidget {
  final Map<String, dynamic> teller;

  const DetailsTellerPage({super.key, required this.teller});

  @override
  State<DetailsTellerPage> createState() => _DetailsTellerPageState();
}

class _DetailsTellerPageState extends State<DetailsTellerPage> {
  TextEditingController amountController = TextEditingController();
  TextEditingController remarksController = TextEditingController();
  String? apiUrl;
  bool updating = false;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('api_url');
    });
  }

  Future<void> updateBalance(String action) async {
  final amount = amountController.text.trim();
  final remarks = remarksController.text.trim();

  if (amount.isEmpty || apiUrl == null) return;

  setState(() => updating = true);

  try {
    final prefs = await SharedPreferences.getInstance();
    final setterUsername = prefs.getString('username') ?? 'admin';

    final response = await http.post(
      Uri.parse('$apiUrl/api/user/balance'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': widget.teller['username'],
        'action': action,
        'amount': double.tryParse(amount),
        'remarks': remarks,
        'setter_username': setterUsername, // <<--- important!
      }),
    );

    final result = jsonDecode(response.body);

    if (response.statusCode == 200) {
      setState(() {
        widget.teller['balance'] = result['new_balance'];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message']), backgroundColor: Colors.green),
      );

      Navigator.pop(context, true); // ✅ trigger refresh in parent
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['error'] ?? 'Unknown error'), backgroundColor: Colors.red),
      );
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Server error: $e"), backgroundColor: Colors.red),
    );
  }

  amountController.clear();
  remarksController.clear();
  setState(() => updating = false);
}

  @override
  Widget build(BuildContext context) {
    final teller = widget.teller;
    final balance = double.tryParse(teller['balance'].toString())?.toStringAsFixed(2) ?? '0.00';

    return Scaffold(
      appBar: AppBar(
        title: Text('Teller: ${teller['username']}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Username: ${teller['username']}", style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 10),
            Text("Status: ${teller['status']}", style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 10),
            Text("Current Balance: ₱$balance", style: const TextStyle(fontSize: 16)),
            const Divider(height: 30),
            TextField(
              controller: amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Amount"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: remarksController,
              decoration: const InputDecoration(labelText: "Remarks (optional)"),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                // ElevatedButton(
                //   onPressed: updating ? null : () => updateBalance("add"),
                //   style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                //   child: const Text("Add"),
                // ),
                // const SizedBox(width: 10),
                // ElevatedButton(
                //   onPressed: updating ? null : () => updateBalance("remove"),
                //   style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                //   child: const Text("Remove"),
                // ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: updating ? null : () => updateBalance("set"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text("Set"),
                ),
              ],
            ),
            if (updating)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(child: CircularProgressIndicator()),
              )
          ],
        ),
      ),
    );
  }
}
