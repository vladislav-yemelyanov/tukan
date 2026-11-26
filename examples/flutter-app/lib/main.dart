import 'package:flutter/material.dart';

import 'services/services.dart';
import 'ui/todos_section.dart';

void main() {
  runApp(TukanExampleApp(appServices: services));
}

class TukanExampleApp extends StatelessWidget {
  final AppServices appServices;

  const TukanExampleApp({
    super.key,
    required this.appServices,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tukan + Flutter Todo Example',
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: TukanHomePage(appServices: appServices),
    );
  }
}

class TukanHomePage extends StatelessWidget {
  final AppServices appServices;

  const TukanHomePage({
    super.key,
    required this.appServices,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tukan + Flutter Todo Example'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TodosSection(appServices: appServices),
        ],
      ),
    );
  }
}
