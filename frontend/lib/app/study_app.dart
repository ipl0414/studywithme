import 'package:flutter/material.dart';

import '../core/api/api_client.dart';
import '../features/shell/study_shell.dart';
import 'theme/meta_theme.dart';

class StudyApp extends StatefulWidget {
  const StudyApp({super.key});

  @override
  State<StudyApp> createState() => _StudyAppState();
}

class _StudyAppState extends State<StudyApp> {
  final _api = ApiClient();
  bool _loggedIn = false;

  void _handleLoggedIn() {
    setState(() => _loggedIn = true);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Character Study',
      debugShowCheckedModeBanner: false,
      theme: MetaTheme.light(),
      home: _loggedIn
          ? StudyShell(api: _api)
          : _LoginScreen(
              api: _api,
              onLoggedIn: _handleLoggedIn,
            ),
    );
  }
}

class _LoginScreen extends StatefulWidget {
  const _LoginScreen({
    required this.api,
    required this.onLoggedIn,
  });

  final ApiClient api;
  final VoidCallback onLoggedIn;

  @override
  State<_LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<_LoginScreen> {
  final _controller = TextEditingController(text: 'test_user');
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final userId = _controller.text.trim();
    if (userId.isEmpty) {
      setState(() => _error = '계정 ID를 입력해줘.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.api.loginWithTestAccount(userId);
      if (mounted) {
        widget.onLoggedIn();
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '로그인에 실패했어. 백엔드 서버를 확인해줘.');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(MetaSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '로그인',
                    style: textTheme.headlineLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MetaSpacing.xs),
                  Text(
                    '계정 ID를 입력해줘. 없으면 새로 만들어져.',
                    style: textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: MetaSpacing.xl),
                  TextField(
                    controller: _controller,
                    enabled: !_loading,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: '계정 ID',
                      prefixIcon: const Icon(Icons.person),
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: MetaSpacing.base),
                  FilledButton.icon(
                    onPressed: _loading ? null : _login,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(_loading ? '로그인 중' : '로그인'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
