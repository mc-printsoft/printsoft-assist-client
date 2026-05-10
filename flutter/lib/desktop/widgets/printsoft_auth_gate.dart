// 0g.14b Etap 1 (10.05.2026): Auth gate dla Printsoft Assist.
//
// Widget owijajacy DesktopTabPage. Sprawdza czy klient jest zalogowany
// (token + deviceId w bind.mainGetOptionSync). Jesli nie - pokazuje
// PrintsoftLoginScreen. Po sukcesie -> przelacza na child.
//
// Uzycie w main.dart:
//   home: isDesktop
//       ? PrintsoftAuthGate(child: const DesktopTabPage())
//       : ...

import 'package:flutter/material.dart';
import 'printsoft_login_screen.dart';

class PrintsoftAuthGate extends StatefulWidget {
  final Widget child;

  const PrintsoftAuthGate({super.key, required this.child});

  @override
  State<PrintsoftAuthGate> createState() => _PrintsoftAuthGateState();
}

class _PrintsoftAuthGateState extends State<PrintsoftAuthGate> {
  bool _checkedLogin = false;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _checkLogin() {
    setState(() {
      _isLoggedIn = isPrintsoftLoggedIn();
      _checkedLogin = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_checkedLogin) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_isLoggedIn) {
      return PrintsoftLoginScreen(
        onSuccess: _checkLogin,
      );
    }
    return widget.child;
  }
}
