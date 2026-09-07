import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/navigation/main_navigation_screen.dart';

class AndroidAIGatewayApp extends StatelessWidget {
  final List<CameraDescription> cameras;

  const AndroidAIGatewayApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Android AI Gateway',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: MainNavigationScreen(cameras: cameras),
    );
  }
}
