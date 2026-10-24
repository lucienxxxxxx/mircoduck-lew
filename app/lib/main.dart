import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'phone_home.dart';
import 'services/robot_connection.dart';
import 'widgets/style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ConsoleApp());
}

class ConsoleApp extends StatelessWidget {
  final RobotConnection? connection;
  const ConsoleApp({super.key, this.connection});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'mircoduck-lew',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: background,
          colorScheme: const ColorScheme.dark(
            primary: cyan,
            secondary: orange,
            surface: panel,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
          ),
        ),
        home: PhoneHome(connection: connection),
      );
}
