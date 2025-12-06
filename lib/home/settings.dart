import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _oldPwController = TextEditingController();
  final TextEditingController _newPwController = TextEditingController();
  final TextEditingController _confirmPwController = TextEditingController();

  bool _changingPw = false;
  String? _pwMsg;
  bool _showOld = false;
  bool _showNew = false;
  bool _showConfirm = false;

  Future<void> _changePassword() async {
    setState(() {
      _changingPw = true;
      _pwMsg = null;
    });

    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString('api_url');
    final username = prefs.getString('username');
    if (apiUrl == null || username == null) {
      setState(() {
        _pwMsg = "Missing API URL or username in settings.";
        _changingPw = false;
      });
      return;
    }
    final oldPw = _oldPwController.text;
    final newPw = _newPwController.text;
    final confirmPw = _confirmPwController.text;

    if (newPw != confirmPw) {
      setState(() {
        _pwMsg = "New passwords do not match.";
        _changingPw = false;
      });
      return;
    }

    try {
      final res = await http.post(
        Uri.parse('$apiUrl/api/change-password'),
        headers: {'Content-Type': 'application/json'},
        body: '{"username":"$username","old_password":"$oldPw","new_password":"$newPw"}',
      );
      if (res.statusCode == 200) {
        setState(() {
          _pwMsg = "Password changed successfully!";
        });
        _oldPwController.clear();
        _newPwController.clear();
        _confirmPwController.clear();
        // Ask if they want to log out
        Future.delayed(const Duration(milliseconds: 400), _askLogout);
      } else {
        setState(() {
          _pwMsg = "Failed: ${res.body}";
        });
      }
    } catch (e) {
      setState(() {
        _pwMsg = "Network error: $e";
      });
    } finally {
      setState(() {
        _changingPw = false;
      });
    }
  }

  Future<void> _askLogout() async {
    if (!mounted) return;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Password Changed"),
        content: const Text("Do you want to log out now?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text("Stay"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text("Log out"),
          ),
        ],
      ),
    );
    if (result == true) {
      final prefs = await SharedPreferences.getInstance();
      final apiUrl = prefs.getString('api_url');
      await prefs.clear();
      if (apiUrl != null) {
        await prefs.setString('api_url', apiUrl);
      }
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
    }
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String label,
    required bool show,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: !show,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        suffixIcon: IconButton(
          icon: Icon(show ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      ),
      style: const TextStyle(fontSize: 16),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F7),
      body: Center(
        child: SingleChildScrollView(
          child: Card(
            elevation: 8,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.settings, size: 46, color: Colors.black87),
                  const SizedBox(height: 10),
                  const Text(
                    "Change Password",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 23,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildPasswordField(
                    controller: _oldPwController,
                    label: "Current Password",
                    show: _showOld,
                    onToggle: () => setState(() => _showOld = !_showOld),
                  ),
                  const SizedBox(height: 16),
                  _buildPasswordField(
                    controller: _newPwController,
                    label: "New Password",
                    show: _showNew,
                    onToggle: () => setState(() => _showNew = !_showNew),
                  ),
                  const SizedBox(height: 16),
                  _buildPasswordField(
                    controller: _confirmPwController,
                    label: "Confirm New Password",
                    show: _showConfirm,
                    onToggle: () => setState(() => _showConfirm = !_showConfirm),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      icon: _changingPw
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.lock_reset),
                      label: Text(
                        _changingPw ? "Changing..." : "Change Password",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: Colors.red[700],
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      onPressed: _changingPw ? null : _changePassword,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: (_pwMsg != null && _pwMsg!.isNotEmpty)
                        ? Padding(
                            key: ValueKey(_pwMsg),
                            padding: const EdgeInsets.only(top: 18),
                            child: Row(
                              children: [
                                Icon(
                                  _pwMsg!.contains("success")
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  color: _pwMsg!.contains("success") ? Colors.green : Colors.red,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _pwMsg!,
                                    style: TextStyle(
                                      color: _pwMsg!.contains("success") ? Colors.green : Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
