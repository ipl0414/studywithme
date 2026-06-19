import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';

/// 기존 캐릭터의 이름/성격/외형을 수정하는 화면.
class CharacterEditScreen extends StatefulWidget {
  const CharacterEditScreen({
    super.key,
    required this.api,
    required this.character,
    required this.onEdited,
  });

  final ApiClient api;
  final CharacterDto character;
  final ValueChanged<CharacterDto> onEdited;

  @override
  State<CharacterEditScreen> createState() => _CharacterEditScreenState();
}

class _CharacterEditScreenState extends State<CharacterEditScreen> {
  late final TextEditingController _name =
      TextEditingController(text: widget.character.name);
  late final TextEditingController _persona =
      TextEditingController(text: widget.character.personaText);
  late final TextEditingController _appearance =
      TextEditingController(text: widget.character.appearanceText);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _persona.dispose();
    _appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: MetaColors.canvas,
      appBar: AppBar(
        backgroundColor: MetaColors.canvas,
        surfaceTintColor: MetaColors.canvas,
        elevation: 0,
        title: const Text('프로필 편집'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(MetaSpacing.xl),
          children: [
            Text('이름, 성격, 외형을 수정합니다.', style: textTheme.bodyLarge),
            const SizedBox(height: MetaSpacing.xl),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '이름'),
            ),
            const SizedBox(height: MetaSpacing.md),
            TextField(
              controller: _persona,
              minLines: 3,
              maxLines: 6,
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
              onPressed: _saving ? null : _save,
              child: Text(_saving ? '저장 중...' : '저장'),
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

  Future<void> _save() async {
    final name = _name.text.trim();
    final persona = _persona.text.trim();
    final appearance = _appearance.text.trim();
    if (name.isEmpty || persona.isEmpty || appearance.isEmpty) {
      setState(() => _error = '이름, 성격, 외형을 모두 입력해 주세요.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await widget.api.updateCharacter(
        characterId: widget.character.id,
        name: name,
        personaText: persona,
        appearanceText: appearance,
      );
      if (!mounted) {
        return;
      }
      widget.onEdited(updated);
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}
