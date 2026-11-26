import 'package:firebase_core/firebase_core.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: QrAttendApp()));
}

class QrAttendApp extends StatelessWidget {
  const QrAttendApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'QR-Attend',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
    home: const Scaffold(body: Center(child: Text('Firebase connected'))),
  );
}