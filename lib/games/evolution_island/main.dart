// Copyright 2024 The Flutter team. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/material.dart';

import 'game_screen.dart';

/// Standalone entry point so the game can be run on its own:
///
/// ```bash
/// flutter run -t lib/games/evolution_island/main.dart
/// ```
void main() {
  runApp(const EvolutionIslandApp());
}

class EvolutionIslandApp extends StatelessWidget {
  const EvolutionIslandApp({Key key}) : super(key: key);

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
