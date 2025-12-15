import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

class ScannerTicketPrintPage extends StatefulWidget {
  final Map<String, dynamic> data;
  final String apiUrl;

  const ScannerTicketPrintPage({
    super.key,
    required this.data,
    required this.apiUrl,
  });

  @override
  State<ScannerTicketPrintPage> createState() => _ScannerTicketPrintPageState();
}

class _ScannerTicketPrintPageState extends State<ScannerTicketPrintPage> {
  String message = "Processing claimed ticket…";
  String? lastError;

  @override
  void initState() {
    super.initState();
    _processClaim();
  }

  Future<void> _processClaim() async {
    try {
      // simulate doing work for realism (optional)
      await Future.delayed(const Duration(milliseconds: 700));

      setState(() => message = "Claim OK — completing…");

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;
      Navigator.pop(context); // return back after success

    } catch (e) {
      lastError = e.toString();
      setState(() => message = "Error: $lastError");

      await Future.delayed(const Duration(seconds: 1));
      if (mounted) Navigator.pop(context);
    }
  }

  String now() {
    return DateFormat('y-MM-dd h:mm a').format(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: lastError == null ? Colors.black : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
