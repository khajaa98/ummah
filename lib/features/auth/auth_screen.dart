// lib/features/auth/auth_screen.dart
// =============================================================================
// AuthScreen — Login and Register UI.
//
// Goes at: lib/features/auth/auth_screen.dart
// (Create the lib/features/auth/ folder — your current lib/services/auth/
// only holds token storage, which is correct. UI lives under features/.)
//
// Wire in main.dart:
//   • After NotificationService.init() but before runApp, check if a token
//     exists via TokenService. If null, push AuthScreen as the first route.
//   • On successful login/register, navigate to your existing UmmahShell.
//
// Features:
//   • Toggle between Login / Register modes
//   • Calls POST /v1/auth/login or POST /v1/auth/register
//   • Saves JWT via TokenService
//   • Inline validation + server-side error display
//   • Fully Material 3 — uses your dynamic theme's ColorScheme
//   • Privacy reassurance note matching the rest of your app's tone
// =============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/constants/api_constants.dart';
import '../../services/auth/token_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.onAuthenticated});

  /// Optional callback invoked on successful login/register.
  /// If not provided, the screen pops itself off the navigation stack.
  final VoidCallback? onAuthenticated;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen>
    with SingleTickerProviderStateMixin {

  final _formKey         = GlobalKey<FormState>();
  final _emailCtrl       = TextEditingController();
  final _passwordCtrl    = TextEditingController();
  final _displayNameCtrl = TextEditingController();

  bool   _isRegister      = false;
  bool   _loading         = false;
  bool   _obscurePassword = true;
  String? _serverError;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _displayNameCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isRegister  = !_isRegister;
      _serverError = null;
      _formKey.currentState?.reset();
    });
    _fadeCtrl.forward(from: 0);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _serverError = null; });

    try {
      final endpoint = _isRegister ? '/v1/auth/register' : '/v1/auth/login';
      final uri      = Uri.parse('${ApiConstants.baseUrl}$endpoint');

      final body = {
        'email':    _emailCtrl.text.trim(),
        'password': _passwordCtrl.text,
        if (_isRegister) 'display_name': _displayNameCtrl.text.trim(),
      };

      final response = await http
          .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 || response.statusCode == 201) {
        final token = json['token'] as String?;
        if (token == null) {
          setState(() => _serverError = 'Server returned no token. Please retry.');
          return;
        }
        await ref.read(tokenServiceProvider).saveToken(token);
        if (!mounted) return;

        if (widget.onAuthenticated != null) {
          widget.onAuthenticated!();
        } else {
          Navigator.of(context).pop();
        }
      } else {
        final error   = json['error'] as Map<String, dynamic>? ?? {};
        final message = error['message'] as String? ?? 'An error occurred. Please retry.';
        setState(() => _serverError = message);
      }
    } on Exception catch (e) {
      setState(() => _serverError = 'Connection failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    Icon(Icons.mosque_rounded, color: scheme.primary, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'Ummah',
                      style: text.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color:      scheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isRegister
                          ? 'Create your account'
                          : 'Sign in to continue',
                      style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 36),

                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_isRegister) ...[
                            _Field(
                              controller:   _displayNameCtrl,
                              label:        'Display name',
                              icon:         Icons.person_outline_rounded,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                if (v.trim().length < 2) return 'At least 2 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                          ],
                          _Field(
                            controller:   _emailCtrl,
                            label:        'Email',
                            icon:         Icons.email_outlined,
                            keyboardType: TextInputType.emailAddress,
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) return 'Required';
                              if (!v.contains('@')) return 'Enter a valid email';
                              return null;
                            },
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            controller:  _passwordCtrl,
                            label:       'Password',
                            icon:        Icons.lock_outline_rounded,
                            obscureText: _obscurePassword,
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscurePassword = !_obscurePassword),
                            ),
                            validator: (v) {
                              if (v == null || v.isEmpty) return 'Required';
                              if (_isRegister && v.length < 8) {
                                return 'At least 8 characters';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),

                    if (_serverError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color:        scheme.errorContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                size: 16, color: scheme.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _serverError!,
                                style: text.bodySmall?.copyWith(color: scheme.onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    FilledButton(
                      onPressed: _loading ? null : _submit,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _loading
                          ? SizedBox(
                              width:  20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color:       scheme.onPrimary,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(_isRegister ? 'Create account' : 'Sign in'),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isRegister
                              ? 'Already have an account? '
                              : "Don't have an account? ",
                          style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        GestureDetector(
                          onTap: _toggleMode,
                          child: Text(
                            _isRegister ? 'Sign in' : 'Register',
                            style: text.bodySmall?.copyWith(
                              color:      scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 32),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color:        scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                        border:       Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shield_outlined, size: 16, color: scheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your email is stored as a one-way hash. '
                              'Your location and prayer activity remain private.',
                              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
  });

  final TextEditingController        controller;
  final String                       label;
  final IconData                     icon;
  final TextInputType?               keyboardType;
  final bool                         obscureText;
  final Widget?                      suffixIcon;
  final String? Function(String?)?   validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:   controller,
      keyboardType: keyboardType,
      obscureText:  obscureText,
      validator:    validator,
      decoration: InputDecoration(
        labelText:  label,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: suffixIcon,
        border:     OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled:     true,
      ),
    );
  }
}
