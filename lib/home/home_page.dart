import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'claimer_history.dart';
import 'claimer_rate.dart';
// Import your pages here
import 'bet.dart';
import 'bet_history.dart';
import 'scanner.dart';
import 'void_bet.dart'; // if you make VoidBetPage in void_bet.dart
import 'tellers.dart';
import 'balance.dart';
import 'request_teller.dart';
import 'request_admin.dart';
// --- Import your settings page ---
import 'settings.dart'; // <--- Add this import (if SettingsPage is in settings.dart)

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? userRole;
  int _currentIndex = 0;
  String? username;
  double? balance;
  bool loadingBalance = false;

  List<BottomNavigationBarItem> navItems = [];
  List<Widget> navPages = [];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadUsernameAndBalance();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';

    List<BottomNavigationBarItem> tempNavItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
    ];
    List<Widget> tempPages = [
      const Center(child: Text('Welcome to GAC Cockpit Arena', style: TextStyle(fontSize: 18))),
    ];

    if (role == 'teller') {
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.sports_mma), label: 'Betting'));
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'History'));
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Request'));
      tempPages.addAll([
        const BettingPage(),
        const BetHistoryPage(),
        const RequestPage(),
      ]);
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: 'Scanner'));
      tempPages.add(const ScannerPage());

      // Add this block for Voiding bets instead of Manual Claim
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.cancel), label: 'Void'));
      tempPages.add(const VoidBetPage()); // You need to implement this page!
    } else if (role == 'admin') {
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Request'));
      tempPages.addAll([
        const RequestPage(),
      ]);
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Logs'));
      tempPages.add(const BalanceLogsPage());
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Tellers'));
      tempPages.add(const TellersPage());
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Requests'));
      tempPages.add(const AdminRequestPage());
    } 
    // ------ CLAIMER NAVBAR ------
    else if (role == 'claimer') {
      tempNavItems = [
        const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        const BottomNavigationBarItem(icon: Icon(Icons.percent), label: 'Take Rate'),
      ];
      tempPages = [
        const ClaimerHistoryPage(),
        const ClaimerTakeRatePage(),
      ];
    }

    if (tempNavItems.length < 2) {
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'));
      tempPages.add(const Center(child: Text('Profile page under construction')));
    }

    // --- Always add settings as the last item ---
    tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'));
    tempPages.add(const SettingsPage());

    setState(() {
      userRole = role;
      navItems = tempNavItems;
      navPages = tempPages;
    });
  }

  Future<void> _loadUsernameAndBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final uname = prefs.getString('username') ?? "User";
    setState(() => username = uname);
    await _fetchBalance(uname);
  }

  Future<void> _fetchBalance(String uname) async {
    setState(() => loadingBalance = true);
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString('api_url');
    if (apiUrl == null) {
      setState(() {
        balance = null;
        loadingBalance = false;
      });
      return;
    }
    try {
      final res = await http.get(Uri.parse('$apiUrl/api/user/balance/logs/$uname'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          balance = double.tryParse(data['calculated_balance'].toString()) ?? 0.0;
          loadingBalance = false;
        });
      } else {
        setState(() {
          balance = null;
          loadingBalance = false;
        });
      }
    } catch (_) {
      setState(() {
        balance = null;
        loadingBalance = false;
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key != 'api_url') {
        await prefs.remove(key);
      }
    }
    if (context.mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  String _formatBalance() {
    if (balance == null) return "--";
    return "₱${balance!.toStringAsFixed(2)}";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black87,
        elevation: 2,
        title: Row(
          children: [
            Expanded(
              child: Text(
                username ?? "User",
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.amber, size: 22),
            const SizedBox(width: 5),
            Text(
              loadingBalance ? "..." : _formatBalance(),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 17,
                color: Colors.white,
                letterSpacing: 0.2,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              tooltip: 'Refresh balance',
              onPressed: () async {
                if (username != null) await _fetchBalance(username!);
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: "Logout",
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: navPages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : navPages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: navItems,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.black,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
