import 'package:flutter/material.dart';
import 'ocr_screen.dart';
import 'voice_screen.dart';
import 'image_emboss_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // All three feature screens
  final List<Widget> _screens = const [
    OCRScreen(),           // Tab 0 — Handwritten → Text
    VoiceToTextPage(),     // Tab 1 — Voice → Text
    ImageEmbossScreen(),   // Tab 2 — Image → G-code
  ];

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps all screens alive — state is preserved when switching tabs
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.deepPurple,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed, // needed for 3+ items
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.draw_outlined),
            activeIcon: Icon(Icons.draw),
            label: 'Handwritten',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_none),
            activeIcon: Icon(Icons.mic),
            label: 'Voice',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.image_outlined),
            activeIcon: Icon(Icons.image),
            label: 'Image',
          ),
        ],
      ),
    );
  }
}
