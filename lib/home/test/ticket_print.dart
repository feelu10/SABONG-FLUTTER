import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class TicketPrintPage extends StatefulWidget {
  final List<Map<String, dynamic>> tickets;

  const TicketPrintPage({super.key, required this.tickets});

  @override
  State<TicketPrintPage> createState() => _TicketPrintPageState();
}

class _TicketPrintPageState extends State<TicketPrintPage> {
  String message = "Submitting bet…";
  String? apiUrl;
  bool submitted = false;
  String? receiptId;
  String? fightNumber;
  String? teller;

  @override
  void initState() {
    super.initState();
    _startSubmission();
  }

  Future<void> _startSubmission() async {
    await _loadApi();
    bool ok = await _submitToBackend();

    if (!ok) {
      setState(() => message = "Bet submission failed.");
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
      return;
    }

    // No printing — just success message
    setState(() => message = "Bet submitted successfully!");

    await Future.delayed(const Duration(seconds: 1));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _loadApi() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString("api_url");
  }

  Future<bool> _submitToBackend() async {
    if (apiUrl == null || submitted) return false;

    try {
      final t = widget.tickets[0];

      final uri = Uri.parse("$apiUrl/api/bet");
      final prefs = await SharedPreferences.getInstance();

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fight_id': t['fight_id'],
          'user': prefs.getString('username') ?? 'teller',
          'side': t['side'],
          'amount': t['amount'],
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          receiptId = data['receipt_id']?.toString();
          fightNumber = t['fight_number']?.toString();
          teller = data['teller']?.toString();
          submitted = true;
        });
        return true;
      }
    } catch (e) {
      print("Bet error: $e");
    }

    return false;
  }

  String _now() {
    final f = DateFormat('MMM d, y • h:mm a');
    return f.format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black.withOpacity(0.85),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              message,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            if (receiptId != null) ...[
              const SizedBox(height: 10),
              Text(
                "Receipt #$receiptId\nFight #$fightNumber",
                style: const TextStyle(color: Colors.white60),
                textAlign: TextAlign.center,
              ),
            ]
          ],
        ),
      ),
    );
  }
}
