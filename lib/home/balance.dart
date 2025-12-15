import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class BalanceLogsPage extends StatefulWidget {
  final String? username;

  const BalanceLogsPage({super.key, this.username});

  @override
  State<BalanceLogsPage> createState() => _BalanceLogsPageState();
}

class _BalanceLogsPageState extends State<BalanceLogsPage> {
  List<dynamic> logs = [];
  bool isLoading = true;
  String? apiUrl;
  String filterAction = 'all'; // all, add, set

  @override
  void initState() {
    super.initState();
    fetchLogs();
  }

  Future<void> fetchLogs() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');
    if (apiUrl == null) return;

    String endpoint = widget.username != null
        ? '$apiUrl/api/user/balance/logs/${widget.username}'
        : '$apiUrl/api/user/balance/logs';

    if (filterAction != 'all') {
      endpoint += '?action=$filterAction';
    }

    try {
      final res = await http.get(Uri.parse(endpoint));
      if (res.statusCode == 200) {
        setState(() {
          logs = jsonDecode(res.body);
          isLoading = false;
        });
      } else {
        throw Exception('Failed to fetch logs');
      }
    } catch (e) {
      print('❌ Error: $e');
      setState(() => isLoading = false);
    }
  }

  Future<void> voidLog(int logId) async {
    if (apiUrl == null) return;

    try {
      final res = await http.post(
        Uri.parse('$apiUrl/api/user/balance/logs/void'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': logId}),
      );

      final result = jsonDecode(res.body);
      if (res.statusCode == 200) {
        fetchLogs();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message']), backgroundColor: Colors.green),
        );
      } else {
        throw Exception(result['error'] ?? 'Failed to void');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Server error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSpecific = widget.username != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isSpecific
            ? 'Balance Logs: ${widget.username}'
            : 'All Balance Logs'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter Dropdown
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text('Filter:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(width: 10),
                DropdownButton<String>(
                  value: filterAction,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => filterAction = value);
                      fetchLogs();
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All')),
                    DropdownMenuItem(value: 'add', child: Text('Add Only')),
                    DropdownMenuItem(value: 'set', child: Text('Set Only')),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : logs.isEmpty
                    ? const Center(child: Text('No balance logs found'))
                    : ListView.separated(
                        padding: const EdgeInsets.all(10),
                        itemCount: logs.length,
                        separatorBuilder: (_, __) => const Divider(),
                        itemBuilder: (context, i) {
                          final log = logs[i];
                          final isVoided = log['deleted_at'] != null;

                          return ListTile(
                            title: Text(
                              '${log['username'] ?? widget.username} • ${log['action'].toUpperCase()} ₱${log['amount']}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (log['remarks'] != null &&
                                    log['remarks'].toString().isNotEmpty)
                                  Text('Remarks: ${log['remarks']}'),
                                Text('Balance After: ₱${log['balance_after']}'),
                                Text('Created: ${log['created_at']}'),
                                if (isVoided)
                                  Text('❌ Voided on: ${log['deleted_at']}',
                                      style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                            trailing: !isVoided
                                ? IconButton(
                                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                                    onPressed: () => voidLog(log['id']),
                                  )
                                : null,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
