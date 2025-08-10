import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/v2ray_provider.dart';
import 'providers/telegram_proxy_provider.dart';
import 'screens/main_navigation_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => V2RayProvider()),
        ChangeNotifierProvider(create: (context) => TelegramProxyProvider()),
      ],
      child: MaterialApp(
        title: 'Proxy Cloud',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const MainNavigationScreen(),
      ),
    );
  }
}
