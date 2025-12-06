import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AdminRequestPage extends StatefulWidget {
  const AdminRequestPage({super.key});

  @override
  State<AdminRequestPage> createState() => _AdminRequestPageState();
}

class _AdminRequestPageState extends State<AdminRequestPage> {
  List<Map<String, dynamic>> requests = [];
  String? apiUrl;

  @override
  void initState() {
    super.initState();
    _loadApiUrl();
  }

  Future<void> _loadApiUrl() async {
    final prefs = await SharedPreferences.getInstance();
    apiUrl = prefs.getString('api_url');
    if (apiUrl != null) {
      await _fetchRequests();
    }
  }

  Future<void> _fetchRequests() async {
    try {
      final url = Uri.parse('$apiUrl/api/request/all');
      final res = await http.get(url);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          requests = List<Map<String, dynamic>>.from(data);
        });
      } else {
        debugPrint('❌ Failed to load: ${res.body}');
      }
    } catch (e) {
      debugPrint('❌ Error loading requests: $e');
    }
  }

  Future<void> _acceptRequest(int requestId) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username'); // or 'admin' hardcoded for now

    final url = Uri.parse('$apiUrl/api/request/$requestId/accept');
    final res = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'approver_username': username}), // required!
    );

    if (res.statusCode == 200) {
      debugPrint("✅ Request accepted");
      await _fetchRequests();
    } else {
      debugPrint('❌ Failed to accept: ${res.body}');
    }
  } catch (e) {
    debugPrint('❌ Error accepting request: $e');
  }
}


  Future<void> _voidRequest(int requestId, String username) async {
    try {
      final url = Uri.parse('$apiUrl/api/request/$requestId/void');
      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );

      if (res.statusCode == 200) {
        debugPrint("🗑️ Request voided");
        await _fetchRequests();
      } else {
        debugPrint('❌ Failed to void: ${res.body}');
      }
    } catch (e) {
      debugPrint('❌ Error voiding request: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchRequests,
      child: ListView.builder(
        itemCount: requests.length,
        itemBuilder: (_, index) {
          final r = requests[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: ListTile(
              title: Text("${r['type'].toUpperCase()} - ₱${r['amount']}"),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("User: ${r['username']}"),
                  Text("Status: ${r['status']}"),
                  const SizedBox(height: 8),
                  if (r['status'] == 'pending')
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () => _acceptRequest(r['id']),
                          child: const Text("Accept"),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () => _voidRequest(r['id'], r['username']),
                          child: const Text("Void"),
                        ),
                      ],
                    ),
                ],
              ),
              trailing: Text(r['created_at']),
              isThreeLine: true,
            ),
          );
        },
      ),
    );
  }
}
