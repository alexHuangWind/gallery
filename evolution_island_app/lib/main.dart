import 'package:flutter/material.dart';

import 'game_screen.dart';

void main() {
  runApp(const EvolutionIslandApp());
}

class EvolutionIslandApp extends StatelessWidget {
  const EvolutionIslandApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '达尔文进化岛',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: const EvolutionIslandGame(),
    );
  }
}
