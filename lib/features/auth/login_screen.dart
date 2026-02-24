import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'auth_controller.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;

  @override
  void initState() {
    super.initState();
    // Check login status on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).checkLoginStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    
    // Redirect if already logged in
    if (authState.isLoggedIn) {
      // Use microtask to avoid build phase navigation
      Future.microtask(() => context.go('/dashboard'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (_otpSent) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _otpController,
                decoration: const InputDecoration(labelText: 'OTP'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final email = _emailController.text;
                  final otp = _otpController.text;
                  if (email.isNotEmpty && otp.isNotEmpty) {
                    final success = await ref.read(authControllerProvider.notifier).verifyOtp(email, otp);
                    if (success) {
                      // Navigate to dashboard
                      context.go('/dashboard');
                    }
                  }
                },
                child: authState.isLoading ? const CircularProgressIndicator() : const Text('Verify'),
              ),
            ] else ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  final email = _emailController.text;
                  if (email.isNotEmpty) {
                    await ref.read(authControllerProvider.notifier).requestOtp(email);
                    if (authState.error == null) {
                      setState(() {
                        _otpSent = true;
                      });
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(authState.error ?? 'Error')));
                    }
                  }
                },
                child: authState.isLoading ? const CircularProgressIndicator() : const Text('Send OTP'),
              ),
            ],
            if (authState.error != null) ...[
              const SizedBox(height: 16),
              Text(authState.error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
