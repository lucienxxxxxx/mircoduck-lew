import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pilot_home.dart';
import 'services/robot_connection.dart';
import 'widgets/startup.dart';
import 'widgets/style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ConsoleApp(showStartup: true));
}

class ConsoleApp extends StatelessWidget {
  final RobotConnection? connection;
  final bool showStartup;
  const ConsoleApp({super.key, this.connection, this.showStartup = false});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '鸭控 · DuckPilot',
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
        home: showStartup
            ? StartupGate(child: PhoneHome(connection: connection))
            : PhoneHome(connection: connection),
      );
}
