import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../home/printer_settings.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String masterApi = "http://72.62.69.106:5000"; //change based on master.py
  String? selectedSiteUrl;

  bool _isLoading = false;
  bool _loadingSites = true;
  bool printerSelected = false;

  List<Map<String, dynamic>> sites = [];

  @override
  void initState() {
    super.initState();
    _loadSavedUsername();
    _loadSavedPrinter();
    _fetchSites();
  }

  Future<void> _loadSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    printerSelected = prefs.getString("printer_address") != null;
    setState(() {});
  }

  Future<void> _fetchSites() async {
    try {
      final response = await http.get(Uri.parse("$masterApi/sites"));
      final data = jsonDecode(response.body);

      setState(() {
        sites = List<Map<String, dynamic>>.from(data["sites"]);
        _loadingSites = false;
      });
    } catch (_) {
      _showError("Unable to load sites.");
    }
  }

  Future<void> _loadSavedUsername() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('username');
    if (saved != null) _usernameController.text = saved;
  }

  // -------------------- LOGIN ---------------------
  Future<void> _login() async {
    final prefs = await SharedPreferences.getInstance();

    if (selectedSiteUrl == null) {
      _showError("Please select a site.");
      return;
    }

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError("Enter username & password.");
      return;
    }

    setState(() => _isLoading = true);

    String cleanUrl = selectedSiteUrl!.trim();

    cleanUrl = cleanUrl
        .replaceAll("http://http://", "http://")
        .replaceAll("https://https://", "https://")
        .replaceAll("://http://", "://")
        .replaceAll("///", "/")
        .replaceAll("::", ":")
        .replaceAll(":5100:5100", ":5100")
        .replaceAll(":5001:5001", ":5001")
        .replaceAll("http//", "http://")
        .replaceAll("https//", "https://");

    print("🔍 CLEANED SITE URL => $cleanUrl");

    // ----------------------------------------------------------
    // Build login URL
    // ----------------------------------------------------------
    final loginUrl = "$cleanUrl/api/login";

    print("🔍 TRY LOGIN URL => $loginUrl");

    try {
      final response = await http.post(
        Uri.parse(loginUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["token"] != null) {
        await prefs.setString("api_url", cleanUrl);
        await prefs.setString("username", data['username'] ?? username);
        await prefs.setString("user_role", data['role'] ?? '');
        await prefs.setBool('isLoggedIn', true);

        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        _showError(data['error'] ?? "Login failed.");
      }
    } catch (e) {
      print("❌ LOGIN ERROR: $e");
      _showError("Unable to reach site.\n$e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Icon(Icons.sports_mma, size: 100, color: Colors.red),
                const SizedBox(height: 20),

                // SITE DROPDOWN
                _loadingSites
                    ? const CircularProgressIndicator(color: Colors.red)
                    : DropdownButtonFormField<String>(
                        value: selectedSiteUrl,
                        dropdownColor: Colors.black87,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decor("Select Site"),
                        items: sites.map((s) {
                          return DropdownMenuItem<String>(
                            value: s["url"].toString(),
                            child: Text(
                              s["site_name"] ?? "Unknown",
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => selectedSiteUrl = v),
                      ),

                const SizedBox(height: 20),

                TextField(
                  controller: _usernameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decor("Username"),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: _decor("Password"),
                ),

                const SizedBox(height: 25),

                // OPTIONAL PRINTER BUTTON (no requirement)
                ElevatedButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PrinterSettingsPage(),
                      ),
                    );
                    _loadSavedPrinter();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        printerSelected ? Colors.green : Colors.blue,
                  ),
                  child: Text(
                    printerSelected
                        ? "Printer Selected ✔"
                        : "Select Printer (optional)",
                  ),
                ),

                const SizedBox(height: 20),

                // ---------------- LOGIN ----------------
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "LOGIN",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _decor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
}
