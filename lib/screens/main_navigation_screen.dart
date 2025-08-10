import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/telegram_proxy_provider.dart';
import '../theme/app_theme.dart';
import 'home_screen.dart';
import 'telegram_proxy_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = [
    const HomeScreen(),
    const TelegramProxyScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.primaryDark,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppTheme.primaryGreen,
          unselectedItemColor: Colors.grey,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.vpn_key),
              label: 'VPN',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.telegram),
              label: 'Proxy',
            ),
          ],
        ),
      ),
    );
  }
}