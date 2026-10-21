import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.projectUrl,
      publishableKey: SupabaseConfig.publishableKey,
    );
  } else {
    debugPrint(
      'Supabase is not initialized. Start the app with SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY.',
    );
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: SignInScreen());
  }
}

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  static const _backgroundColor = Color.fromARGB(255, 26, 11, 42);
  static const _labelColor = Color.fromARGB(255, 160, 123, 225);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      // Let the scaffold resize its body when the on-screen keyboard appears.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              fit: StackFit.expand,
              children: [
                const Positioned(
                  top: -45,
                  right: -85,
                  child: _Glow(
                    size: 250,
                    color: Color.fromARGB(226, 217, 8, 228),
                    spreadRadius: 50,
                  ),
                ),
                const Positioned(
                  bottom: -105,
                  left: -145,
                  child: _Glow(
                    size: 300,
                    color: Color.fromARGB(226, 12, 18, 182),
                    spreadRadius: 65,
                  ),
                ),
                SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 24,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 48,
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Welcome',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 37,
                              fontWeight: FontWeight.bold,
                              color: Color.fromARGB(255, 170, 137, 227),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 440),
                            child: const _SignInCard(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard();

  static const _labelStyle = TextStyle(
    fontSize: 25,
    color: SignInScreen._labelColor,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('sign-in-card'),
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 450),
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 48),
      decoration: BoxDecoration(
        color: const Color.fromARGB(149, 87, 37, 141),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Align(
            alignment: Alignment.topCenter,
            child: Text(
              'Sign in / Login',
              style: TextStyle(
                color: Color.fromARGB(255, 132, 92, 202),
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Email', style: _labelStyle),
          const TextField(
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Enter your Email',
              filled: true,
              fillColor: SignInScreen._labelColor,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 35),
          const Text('Mot de passe', style: _labelStyle),
          const TextField(
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Enter your password',
              filled: true,
              fillColor: SignInScreen._labelColor,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          const Align(
            alignment: Alignment.topCenter,
            child: Text(
              'Or with',
              style: TextStyle(fontSize: 20, color: SignInScreen._labelColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({
    required this.size,
    required this.color,
    required this.spreadRadius,
  });

  final double size;
  final Color color;
  final double spreadRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color, blurRadius: 135, spreadRadius: spreadRadius),
        ],
      ),
    );
  }
}
