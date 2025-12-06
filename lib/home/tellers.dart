import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'details_teller.dart';

class TellersPage extends StatefulWidget {
  const TellersPage({super.key});

  @override
  State<TellersPage> createState() => _TellersPageState();
}

class _TellersPageState extends State<TellersPage> {
  List<Map<String, dynamic>> tellers = [];
  bool isLoading = true;
  String? apiUrl;

  @override
  void initState() {
    super.initState();
    loadTellers();
  }

  Future<void> loadTellers() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');

    if (apiUrl == null) return;

    try {
      final res = await http.get(Uri.parse('$apiUrl/api/users'));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final tellerUsers = (data as List)
            .where((u) => u['role'] == 'teller')
            .toList();

        // Fetch calculated balances for each teller
        final List<Map<String, dynamic>> updatedTellers = [];
        for (final teller in tellerUsers) {
          final balanceRes = await http.get(
            Uri.parse('$apiUrl/api/user/balance/logs/${teller['username']}'),
          );
          final balanceData = balanceRes.statusCode == 200
              ? jsonDecode(balanceRes.body)
              : null;
          final calculatedBalance = balanceData != null
              ? double.tryParse(balanceData['calculated_balance'].toString()) ?? 0.0
              : 0.0;

          // Always make it Map<String, dynamic>
          updatedTellers.add({
            ...Map<String, dynamic>.from(teller),
            'balance': calculatedBalance.toStringAsFixed(2),
          });
        }

        setState(() {
          tellers = updatedTellers;
          isLoading = false;
        });
      } else {
        throw Exception("Failed to load users");
      }
    } catch (e) {
      print("Error: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: loadTellers,
              child: ListView.builder(
                itemCount: tellers.length,
                itemBuilder: (context, index) {
                  final teller = tellers[index];
                  final balance = double.tryParse(teller['balance'].toString())?.toStringAsFixed(2) ?? '0.00';

                  return ListTile(
                    leading: const Icon(Icons.person),
                    title: Text(teller['username'] ?? ""),
                    subtitle: Text("Balance: ₱$balance"),
                    trailing: Text(
                      teller['status'] ?? "",
                      style: TextStyle(
                        color: teller['status'] == 'active' ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DetailsTellerPage(
                            teller: Map<String, dynamic>.from(teller),
                          ),
                        ),
                      );

                      if (result == true) {
                        setState(() => isLoading = true);
                        await loadTellers(); // ✅ Full refresh after update
                      }
                    },
                  );
                },
              ),
            ),
    );
  }
}
