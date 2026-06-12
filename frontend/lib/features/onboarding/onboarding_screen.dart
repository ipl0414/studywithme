import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.api,
    required this.onCreated,
    this.title = 'Create your tutor',
    this.submitLabel = '캐릭터 생성',
  });

  final ApiClient api;
  final ValueChanged<CharacterDto> onCreated;
  final String title;
  final String submitLabel;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _name = TextEditingController(text: 'Tutor');
  final _gender = TextEditingController(text: '여성');
  final _persona =
      TextEditingController(text: '차갑지만 은근히 챙겨주는 선배 튜터. 짧고 담백하게 말한다.');
  final _appearance =
      TextEditingController(text: '은발, 단정한 복장, 차분한 표정의 2D tutor character');
  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _gender.dispose();
    _persona.dispose();
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MetaSpacing.xl),
          children: [
            Text(widget.title, style: textTheme.headlineLarge),
            const SizedBox(height: MetaSpacing.md),
            Text(
              '이름, 성별, 성격과 외형만 입력하면 캐릭터와 바로 시작합니다.',
              style: textTheme.bodyLarge,
            ),
            const SizedBox(height: MetaSpacing.xxl),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '이름'),
            ),
            const SizedBox(height: MetaSpacing.md),
            TextField(
              controller: _gender,
              decoration: const InputDecoration(labelText: '성별'),
            ),
            const SizedBox(height: MetaSpacing.md),
            TextField(
              controller: _persona,
              minLines: 3,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '성격 / 말투'),
            ),
            const SizedBox(height: MetaSpacing.md),
            TextField(
              controller: _appearance,
              minLines: 3,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '외형'),
            ),
            const SizedBox(height: MetaSpacing.xl),
            FilledButton(
              onPressed: _creating ? null : _create,
              child: Text(_creating ? '생성 중...' : widget.submitLabel),
            ),
            if (_error != null) ...[
              const SizedBox(height: MetaSpacing.md),
              Text(
                _error!,
                style:
                    textTheme.bodyMedium?.copyWith(color: MetaColors.critical),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final gender = _gender.text.trim();
      final persona = _persona.text.trim();
      final character = await widget.api.createCharacter(
        name: _name.text.trim().isEmpty ? 'Tutor' : _name.text.trim(),
        personaText: gender.isEmpty ? persona : '성별: $gender\n$persona',
        appearanceText: _appearance.text.trim(),
      );
      if (!mounted) {
        return;
      }
      widget.onCreated(character);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }
}
