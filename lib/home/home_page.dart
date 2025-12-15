import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'printer_settings.dart';
import 'claimer_history.dart';
import 'claimer_rate.dart';
import 'bet.dart';
import 'bet_history.dart';
import 'scanner.dart';
import 'void_bet.dart';
import 'tellers.dart';
import 'balance.dart';
import 'request_teller.dart';
import 'request_admin.dart';
import 'settings.dart';
import 'home_dashboard.dart'; 
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

  Timer? _pollTimer;

  List<BottomNavigationBarItem> navItems = [];
  List<Widget> navPages = [];

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadUsernameAndBalance();

    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _safeAutoRefresh();
    });
  }

  Future<void> _safeAutoRefresh() async {
    if (!mounted) return;

    final pagesNeedingAutoRefresh = {
      "teller": [0, 1, 2, 3, 4],
      "admin": [0, 1, 2, 3],
      "claimer": [0]
    };

    if (userRole != null &&
        pagesNeedingAutoRefresh.containsKey(userRole) &&
        pagesNeedingAutoRefresh[userRole]!.contains(_currentIndex)) {
      if (username != null) {
        await _fetchBalance(username!);
      }
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('user_role') ?? '';

    List<BottomNavigationBarItem> tempNavItems = [
      const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
    ];
    List<Widget> tempPages = [
      const HomeDashboardPage(),
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
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.cancel), label: 'Void'));
      tempPages.add(const VoidBetPage());
    } else if (role == 'admin') {
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.request_page), label: 'Request'));
      tempPages.add(const RequestPage());
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'Logs'));
      tempPages.add(const BalanceLogsPage());
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Tellers'));
      tempPages.add(const TellersPage());
      tempNavItems.add(const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Requests'));
      tempPages.add(const AdminRequestPage());
    } else if (role == 'claimer') {
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

    // Existing settings
    tempNavItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.settings), label: 'Settings'));
    tempPages.add(const SettingsPage());

    tempNavItems.add(const BottomNavigationBarItem(
        icon: Icon(Icons.print), label: 'Printer'));
    tempPages.add(const PrinterSettingsPage());


    setState(() {
      userRole = role;
      navItems = tempNavItems;
      navPages = tempPages;
    });
  }

  Future<void> _loadUsernameAndBalance() async {
    final prefs = await SharedPreferences.getInstance();
    final uname = prefs.getString('username') ?? "User";
    username = uname;
    setState(() {});
    await _fetchBalance(uname);
  }

  Future<void> _fetchBalance(String uname) async {
    final prefs = await SharedPreferences.getInstance();
    final apiUrl = prefs.getString('api_url');
    if (apiUrl == null) return;

    try {
      final res = await http.get(Uri.parse('$apiUrl/api/user/balance/logs/$uname'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final newBalance = double.tryParse(data['calculated_balance'].toString()) ?? 0.0;

        if (balance != newBalance) {
          setState(() {
            balance = newBalance;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();

    // Keep API URL before clearing
    final apiUrl = prefs.getString('api_url');

    await prefs.clear();
    if (apiUrl != null) {
      await prefs.setString('api_url', apiUrl);
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
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.account_balance_wallet_rounded, color: Colors.amber, size: 22),
            const SizedBox(width: 5),
            Text(
              _formatBalance(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            IconButton(
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white70),
              onPressed: () async {
                if (username != null) await _fetchBalance(username!);
              },
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: navPages.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : navPages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() => _currentIndex = index);
          _safeAutoRefresh();
        },
        items: navItems,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.black,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}
