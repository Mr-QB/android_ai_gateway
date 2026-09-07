import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../camera/presentation/camera_screen.dart';
import '../vlm/presentation/vlm_test_page.dart';

class MainNavigationScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const MainNavigationScreen({super.key, required this.cameras});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          CameraScreen(cameras: widget.cameras),
          const VlmTestPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'YOLO Camera',
          ),
          NavigationDestination(
            icon: Icon(Icons.psychology_outlined),
            selectedIcon: Icon(Icons.psychology),
            label: 'VLM Test',
          ),
        ],
      ),
    );
  }
}
