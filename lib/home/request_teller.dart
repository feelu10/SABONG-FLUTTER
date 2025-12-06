import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RequestPage extends StatefulWidget {
  const RequestPage({super.key});

  @override
  State<RequestPage> createState() => _RequestPageState();
}

class _RequestPageState extends State<RequestPage> {
  List<Map<String, dynamic>> requests = [];
  String? apiUrl;
  String balance = '0.00';

  @override
  void initState() {
    super.initState();
    _loadApiUrlAndFetch();
  }

  Future<void> _loadApiUrlAndFetch() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('api_url');
    });
    await _loadBalance();
    await _fetchRequests();
  }

  Future<void> _loadBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');
    final api = prefs.getString('api_url');

    if (username == null || api == null) return;

    try {
      final res = await http.get(Uri.parse('$api/api/user/balance/logs/$username'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final calculatedBalance = double.tryParse(data['calculated_balance'].toString()) ?? 0.0;

        setState(() {
          balance = calculatedBalance.toStringAsFixed(2);
        });
      }
    } catch (e) {
      print('Error getting balance: $e');
    }
  }

  Future<void> _fetchRequests() async {
    if (apiUrl == null) return;

    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');

    final url = Uri.parse('$apiUrl/api/request/my?username=$username');
    print('🔄 Fetching requests from $url');

    try {
      final response = await http.get(url);
      print('🔄 Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        setState(() {
          requests = data.map((item) => Map<String, dynamic>.from(item)).toList();
        });
      } else {
        print('❌ Failed to fetch requests: ${response.body}');
      }
    } catch (e) {
      print('❌ Error fetching requests: $e');
    }
  }

  Future<void> _submitRequest(String type) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Enter $type amount'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: 'Enter amount'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final value = double.tryParse(controller.text);
              final prefs = await SharedPreferences.getInstance();
              final username = prefs.getString('username');

              if (value != null && value > 0 && apiUrl != null && username != null) {
                if (type == 'cashout') {
                  final balanceVal = double.tryParse(balance) ?? 0.0;

                  if (value > balanceVal) {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text('Insufficient Balance'),
                        content: Text('Your balance is ₱${balanceVal.toStringAsFixed(2)}. You cannot cash out ₱${value.toStringAsFixed(2)}.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                        ],
                      ),
                    );
                    return;
                  }
                }

                final url = Uri.parse('$apiUrl/api/request');
                final body = jsonEncode({
                  'type': type,
                  'amount': value,
                  'username': username,
                });
                print('📤 Submitting $type request: $body to $url');

                try {
                  final res = await http.post(
                    url,
                    headers: {'Content-Type': 'application/json'},
                    body: body,
                  );
                  print('📤 Status: ${res.statusCode}');
                  print('📤 Response: ${res.body}');

                  if (res.statusCode == 201) {
                    Navigator.pop(context);
                    await _loadBalance(); // refresh balance
                    _fetchRequests();
                  } else {
                    print('❌ Failed to submit request');
                  }
                } catch (e) {
                  print('❌ Exception during submit: $e');
                }
              }
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  Future<void> _voidRequest(int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Void Request'),
        content: const Text('Are you sure you want to void this request?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Void')),
        ],
      ),
    );

    if (confirmed == true && apiUrl != null) {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');

      final url = Uri.parse('$apiUrl/api/request/$id/void');
      print('🚫 Sending void request to $url');

      try {
        final res = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'username': username}),
        );
        print('🚫 Status: ${res.statusCode}');
        print('🚫 Response: ${res.body}');

        if (res.statusCode == 200) {
          await _loadBalance(); // refresh balance
          _fetchRequests();
        } else {
          final error = jsonDecode(res.body)['error'] ?? 'Unable to void request';
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Failed'),
              content: Text(error),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          );
        }
      } catch (e) {
        print('❌ Error voiding request: $e');
      }
    }
  }

  Widget _buildRequestTile(Map<String, dynamic> request) {
    final isCashIn = request['type'] == 'cashin';
    final status = request['status'];

    Color statusColor;
    String statusLabel;

    switch (status) {
      case 'voided':
        statusColor = Colors.grey;
        statusLabel = 'Voided';
        break;
      case 'approved':
        statusColor = Colors.green;
        statusLabel = 'Approved';
        break;
      case 'rejected':
        statusColor = Colors.red;
        statusLabel = 'Rejected';
        break;
      default:
        statusColor = Colors.orange;
        statusLabel = 'Pending';
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: Icon(
          isCashIn ? Icons.arrow_downward : Icons.arrow_upward,
          color: isCashIn ? Colors.green : Colors.red,
        ),
        title: Text(
          '${isCashIn ? 'Cash In' : 'Cash Out'} - ₱${request['amount'].toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('Status: $statusLabel', style: TextStyle(color: statusColor)),
        trailing: status == 'pending'
            ? ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade800),
                onPressed: () => _voidRequest(request['id']),
                child: const Text('Void'),
              )
            : Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  'Available Balance: ₱$balance',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => _submitRequest('cashin'),
                      icon: const Icon(Icons.arrow_downward, color: Colors.white),
                      label: const Text('Cash In'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _submitRequest('cashout'),
                      icon: const Icon(Icons.arrow_upward, color: Colors.white),
                      label: const Text('Cash Out'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: requests.isEmpty
                ? const Center(child: Text('No requests yet'))
                : RefreshIndicator(
                    onRefresh: () async {
                      await _loadBalance();
                      await _fetchRequests();
                    },
                    child: ListView.builder(
                      itemCount: requests.length,
                      itemBuilder: (context, index) => _buildRequestTile(requests[index]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
