import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

class ClaimerHistoryPage extends StatefulWidget {
  const ClaimerHistoryPage({super.key});

  @override
  State<ClaimerHistoryPage> createState() => _ClaimerHistoryPageState();
}

class _ClaimerHistoryPageState extends State<ClaimerHistoryPage> {
  double? calculatedAmount;
  double? hannahsAmount;
  double? totalBets;
  bool loading = true;
  String? error;

  List<Map<String, dynamic>> hannahRequests = [];
  bool loadingRequests = false;
  String? username; // current logged-in user

  String formatAmount(num? value) {
    if (value == null) return '--';
    if (value % 1 == 0) {
      return NumberFormat("#,##0", "en_US").format(value);
    } else {
      return NumberFormat("#,##0.##", "en_US").format(value);
    }
  }

  @override
  void initState() {
    super.initState();
    fetchBothAmounts();
    fetchRequests();
  }

  Future<void> fetchBothAmounts() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      username = prefs.getString('username');
      if (apiUrl == null || username == null) {
        setState(() {
          error = "Missing API URL or username.";
          loading = false;
        });
        return;
      }
      final resUser = await http.get(Uri.parse('$apiUrl/api/user/balance/logs/$username'));
      final resAdmin = await http.get(Uri.parse('$apiUrl/api/user/balance/logs/admin'));
      double? _calcAmount;
      double? _hannahs;
      double? _totalBets;
      if (resUser.statusCode == 200) {
        final data = jsonDecode(resUser.body);
        _calcAmount = (data['calculated_balance'] as num?)?.toDouble();
        _totalBets = (data['total_bets'] as num?)?.toDouble();
      }
      if (resAdmin.statusCode == 200) {
        final data = jsonDecode(resAdmin.body);
        _hannahs = (data['calculated_balance'] as num?)?.toDouble();
      }
      setState(() {
        calculatedAmount = _calcAmount;
        hannahsAmount = _hannahs;
        totalBets = _totalBets;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = "Error: $e";
        loading = false;
      });
    }
  }

  Future<void> fetchRequests() async {
    setState(() => loadingRequests = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      if (apiUrl == null) {
        setState(() => loadingRequests = false);
        return;
      }
      final res = await http.get(Uri.parse('$apiUrl/api/request/all'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          setState(() {
            hannahRequests = List<Map<String, dynamic>>.from(data)
                .where((r) => r['username'] == 'admin')
                .toList();
            loadingRequests = false;
          });
        } else {
          setState(() {
            hannahRequests = [];
            loadingRequests = false;
          });
        }
      } else {
        setState(() => loadingRequests = false);
      }
    } catch (e) {
      setState(() => loadingRequests = false);
    }
  }

  Future<void> refresh() async {
    await fetchBothAmounts();
    await fetchRequests();
  }

  void _showAddBalanceDialog({required String username, required String displayName}) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Add Balance for $displayName"),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: "Enter amount",
          ),
        ),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            child: const Text("Add"),
            onPressed: () async {
              String input = controller.text.trim();
              if (input.isEmpty || double.tryParse(input) == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Please enter a valid amount.")),
                );
                return;
              }
              Navigator.of(ctx).pop();
              setState(() => loading = true);
              final prefs = await SharedPreferences.getInstance();
              final apiUrl = prefs.getString('api_url');
              try {
                final response = await http.post(
                  Uri.parse('$apiUrl/api/user/set-balance'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'username': username,
                    'amount': double.parse(input),
                    'setter_username': this.username,  // 👈 current logged-in user
                  }),
                );  
                if (response.statusCode == 200) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("$displayName's wallet set successfully!")),
                  );
                  refresh(); // Reload values
                } else {
                  final err = jsonDecode(response.body)['error'] ?? 'Unknown error';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Failed: $err")),
                  );
                  setState(() => loading = false);
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Network error: $e")),
                );
                setState(() => loading = false);
              }
            },
          ),
        ],
      ),
    );
  }

  // Accept request
  Future<void> acceptRequest(int reqId) async {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString('api_url');
    final approver = username;
    if (apiUrl == null || approver == null) return;
    final res = await http.post(
      Uri.parse('$apiUrl/api/request/$reqId/accept'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'approver_username': approver}),
    );
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request accepted!")),
      );
      refresh();
    } else {
      String msg = "Failed to accept: ";
      try {
        msg += jsonDecode(res.body)['error'] ?? res.body;
      } catch (_) {
        msg += res.body;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // Void request
  Future<void> voidRequest(int reqId) async {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString('api_url');
    final user = username;
    if (apiUrl == null || user == null) return;
    final res = await http.post(
      Uri.parse('$apiUrl/api/request/$reqId/void'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': user}),
    );
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request voided.")),
      );
      refresh();
    } else {
      String msg = "Failed to void: ";
      try {
        msg += jsonDecode(res.body)['error'] ?? res.body;
      } catch (_) {
        msg += res.body;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> req) {
  Color statusColor;
  String statusLabel;
  if (req['status'] == 'approved') {
    statusColor = Colors.green;
    statusLabel = 'Approved';
  } else if (req['status'] == 'voided') {
    statusColor = Colors.red;
    statusLabel = 'Voided';
  } else {
    statusColor = Colors.orange;
    statusLabel = req['status'].toString().toUpperCase();
  }
  String date = req['created_at'] ?? '';
  String voidedAt = req['voided_at'] ?? '';

  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                req['type'] == 'cashin' ? Icons.arrow_downward : Icons.arrow_upward,
                color: req['type'] == 'cashin' ? Colors.blue : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "${req['type'].toString().toUpperCase()} | ₱${formatAmount(req['amount'])}",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text("By: ${req['username']}"),
          Text("Date: $date"),
          if (voidedAt.isNotEmpty)
            Text("Voided at: $voidedAt", style: TextStyle(color: Colors.red[400], fontSize: 13)),
          if (req['status'] == 'pending') ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () => acceptRequest(req['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Accept'),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => voidRequest(req['id']),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    textStyle: const TextStyle(fontSize: 12),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Void'),
                ),
              ],
            ),
          ]
        ],
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    String formattedAmount = formatAmount(calculatedAmount);
    String formattedHannahs = formatAmount(hannahsAmount);
    String formattedTotalBets = formatAmount(totalBets);

    return Scaffold(
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 90),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        const SizedBox(height: 60),
                        Icon(
                          Icons.account_balance_wallet,
                          size: 60,
                          color: Colors.amber[700],
                        ),
                        const SizedBox(height: 30),
                        Center(
                          child: Text(
                            calculatedAmount == null
                                ? '--'
                                : "₱$formattedAmount",
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.normal,
                              color: Color.fromARGB(255, 255, 255, 255),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Your Current Calculated Amount',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        if (totalBets != null) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: Text(
                              "Current Bets: ₱$formattedTotalBets",
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add Balance'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                            onPressed: () async {
                              final prefs = await SharedPreferences.getInstance();
                              final username = prefs.getString('username') ?? '';
                              _showAddBalanceDialog(username: username, displayName: "Your");
                            },
                          ),
                        ),
                        const SizedBox(height: 30),
                        const Divider(height: 1),
                        const SizedBox(height: 30),
                        Icon(
                          Icons.account_circle_outlined,
                          size: 54,
                          color: Colors.purple[400],
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: Text(
                            hannahsAmount == null
                                ? '--'
                                : "₱$formattedHannahs",
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.normal,
                              color: Color.fromARGB(255, 255, 255, 255),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Text(
                            "Hannah's Balance",
                            style: TextStyle(
                              fontSize: 17,
                              color: const Color.fromARGB(255, 255, 255, 255),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text("Add to Hannah's"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                            ),
                            onPressed: () {
                              _showAddBalanceDialog(username: "admin", displayName: "Hannah");
                            },
                          ),
                        ),
                        const SizedBox(height: 32),

                        if (hannahRequests.isNotEmpty) ...[
                          const Divider(height: 1, thickness: 2),
                          const SizedBox(height: 10),
                          Center(
                            child: Text(
                              "Hannah's Requests",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                color: Colors.purple[200],
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...hannahRequests.map(_buildRequestCard).toList(),
                        ],
                        if (!loadingRequests && hannahRequests.isEmpty)
                          Center(
                            child: Text(
                              "No requests for Hannah.",
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ),
                        if (loadingRequests)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
    );
  }
}
