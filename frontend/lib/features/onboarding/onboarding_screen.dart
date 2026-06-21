import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';

/// 튜터 생성 3단계 위저드.
/// 1) 기본 정보(성별·이름) → 2) 성격/말투(관계·호칭·성격) → 3) 외형(선택형).
/// 선택값은 persona_text / appearance_text 문자열로 합쳐 생성 API로 보낸다.
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

const _hairStyles = ['단발', '긴 생머리', '포니테일', '트윈테일'];
const _hairColors = ['검은색', '갈색', '노란색', '은색'];
const _impressions = ['부드러운', '중간', '강한'];
const _accessories = ['안경', '귀걸이', '피어싱', '모자'];

const _femaleColor = Color(0xFFE8546B);
const _maleColor = Color(0xFF3B82F6);

// 전반적으로 밝은 피부 톤(밝음 → 약간 어두움 순).
const _skinTones = <_SkinTone>[
  _SkinTone('매우 밝은', Color(0xFFFFF1E6)),
  _SkinTone('밝은', Color(0xFFFFE0C9)),
  _SkinTone('중간', Color(0xFFF4CBA6)),
  _SkinTone('약간 어두운', Color(0xFFE0B083)),
];

class _SkinTone {
  const _SkinTone(this.label, this.color);
  final String label;
  final Color color;
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;

  // 1단계
  String _gender = '여성';
  final _name = TextEditingController(text: 'Tutor');

  // 2단계
  final _relationship = TextEditingController();
  final _nickname = TextEditingController();
  final _persona =
      TextEditingController(text: '차갑지만 은근히 챙겨주는 선배 튜터. 짧고 담백하게 말한다.');

  // 3단계
  String _hairStyle = _hairStyles.first;
  String _hairColor = _hairColors.first;
  int _skinToneIndex = 1;
  String _impression = '중간';
  final Set<String> _accessory = {};

  bool _creating = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _relationship.dispose();
    _nickname.dispose();
    _persona.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isLast = _step == 2;

    return Scaffold(
      backgroundColor: MetaColors.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                MetaSpacing.xl,
                MetaSpacing.xl,
                MetaSpacing.xl,
                MetaSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: textTheme.headlineMedium),
                  const SizedBox(height: MetaSpacing.md),
                  _StepIndicator(step: _step),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: MetaSpacing.xl),
                children: [
                  switch (_step) {
                    0 => _buildBasicStep(textTheme),
                    1 => _buildPersonaStep(textTheme),
                    _ => _buildAppearanceStep(textTheme),
                  },
                  if (_error != null) ...[
                    const SizedBox(height: MetaSpacing.md),
                    Text(
                      _error!,
                      style: textTheme.bodyMedium
                          ?.copyWith(color: MetaColors.critical),
                    ),
                  ],
                  const SizedBox(height: MetaSpacing.xl),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(MetaSpacing.xl),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _creating
                          ? null
                          : () => setState(() {
                                _step -= 1;
                                _error = null;
                              }),
                      child: const Text('이전'),
                    )
                  else if (Navigator.of(context).canPop())
                    OutlinedButton(
                      onPressed:
                          _creating ? null : () => Navigator.of(context).pop(),
                      child: const Text('취소'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _creating ? null : _onPrimaryPressed,
                    child: Text(
                      _creating
                          ? '생성 중...'
                          : isLast
                              ? widget.submitLabel
                              : '다음',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- 1단계: 기본 정보 ----
  Widget _buildBasicStep(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('기본 정보', style: textTheme.titleLarge),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('이름'),
        TextField(
          controller: _name,
          decoration: const InputDecoration(hintText: '튜터 이름'),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('성별'),
        Wrap(
          spacing: MetaSpacing.xs,
          children: [
            _genderChip('여성', _femaleColor),
            _genderChip('남성', _maleColor),
          ],
        ),
      ],
    );
  }

  Widget _genderChip(String label, Color color) {
    final selected = _gender == label;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      selectedColor: color,
      labelStyle: TextStyle(
        color: selected ? MetaColors.canvas : MetaColors.ink,
        fontWeight: FontWeight.w700,
      ),
      onSelected: (_) => setState(() => _gender = label),
    );
  }

  // ---- 2단계: 성격 / 말투 ----
  Widget _buildPersonaStep(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('성격 / 말투', style: textTheme.titleLarge),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('나와의 관계'),
        TextField(
          controller: _relationship,
          decoration: const InputDecoration(hintText: '예: 후배, 선배, 동기, 소꿉친구'),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('나를 부르는 호칭'),
        TextField(
          controller: _nickname,
          decoration: const InputDecoration(hintText: '예: 선배, 너, 후배님'),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('성격'),
        TextField(
          controller: _persona,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: '성격과 말투를 자유롭게 적어주세요.',
          ),
        ),
      ],
    );
  }

  // ---- 3단계: 외형 ----
  Widget _buildAppearanceStep(TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('외형', style: textTheme.titleLarge),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('머리스타일'),
        _SingleChoice(
          options: _hairStyles,
          selected: _hairStyle,
          onSelected: (value) => setState(() => _hairStyle = value),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('머리색'),
        _SingleChoice(
          options: _hairColors,
          selected: _hairColor,
          onSelected: (value) => setState(() => _hairColor = value),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('피부색'),
        Wrap(
          spacing: MetaSpacing.xs,
          runSpacing: MetaSpacing.xs,
          children: List.generate(_skinTones.length, (index) {
            final tone = _skinTones[index];
            return ChoiceChip(
              label: Text(tone.label),
              selected: _skinToneIndex == index,
              avatar: CircleAvatar(backgroundColor: tone.color),
              onSelected: (_) => setState(() => _skinToneIndex = index),
            );
          }),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('인상'),
        _SingleChoice(
          options: _impressions,
          selected: _impression,
          onSelected: (value) => setState(() => _impression = value),
        ),
        const SizedBox(height: MetaSpacing.lg),
        _FieldLabel('악세사리 (여러 개 선택 가능)'),
        Wrap(
          spacing: MetaSpacing.xs,
          runSpacing: MetaSpacing.xs,
          children: _accessories.map((item) {
            final selected = _accessory.contains(item);
            return FilterChip(
              label: Text(item),
              selected: selected,
              onSelected: (value) => setState(() {
                if (value) {
                  _accessory.add(item);
                } else {
                  _accessory.remove(item);
                }
              }),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _onPrimaryPressed() {
    if (_step < 2) {
      // 단계별 최소 검증.
      if (_step == 0 && _name.text.trim().isEmpty) {
        setState(() => _error = '이름을 입력해 주세요.');
        return;
      }
      if (_step == 1 && _persona.text.trim().isEmpty) {
        setState(() => _error = '성격을 입력해 주세요.');
        return;
      }
      setState(() {
        _step += 1;
        _error = null;
      });
      return;
    }
    _create();
  }

  String _composePersona() {
    final lines = <String>['성별: $_gender'];
    final relationship = _relationship.text.trim();
    if (relationship.isNotEmpty) {
      lines.add('나와의 관계: $relationship');
    }
    final nickname = _nickname.text.trim();
    if (nickname.isNotEmpty) {
      lines.add('나를 부르는 호칭: $nickname');
    }
    final persona = _persona.text.trim();
    if (persona.isNotEmpty) {
      lines.add('성격: $persona');
    }
    return lines.join('\n');
  }

  String _composeAppearance() {
    final parts = <String>[
      '머리스타일: $_hairStyle',
      '머리색: $_hairColor',
      '피부톤: ${_skinTones[_skinToneIndex].label}',
      '인상: $_impression',
    ];
    if (_accessory.isNotEmpty) {
      parts.add('악세사리: ${_accessory.join(', ')}');
    }
    return parts.join(', ');
  }

  Future<void> _create() async {
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final name = _name.text.trim().isEmpty ? 'Tutor' : _name.text.trim();
      final character = await widget.api.createCharacter(
        name: name,
        personaText: _composePersona(),
        appearanceText: _composeAppearance(),
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

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  static const _titles = ['기본 정보', '성격 / 말투', '외형'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(_titles.length, (index) {
        final active = index <= step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index < _titles.length - 1 ? 6 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? MetaColors.primary : MetaColors.hairlineSoft,
                    borderRadius: BorderRadius.circular(MetaRadii.full),
                  ),
                ),
                const SizedBox(height: MetaSpacing.xs),
                Text(
                  '${index + 1}. ${_titles[index]}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: active ? MetaColors.inkDeep : MetaColors.stone,
                        fontWeight:
                            index == step ? FontWeight.w700 : FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MetaSpacing.xs),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _SingleChoice extends StatelessWidget {
  const _SingleChoice({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String? selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: MetaSpacing.xs,
      runSpacing: MetaSpacing.xs,
      children: options
          .map(
            (option) => ChoiceChip(
              label: Text(option),
              selected: selected == option,
              onSelected: (_) => onSelected(option),
            ),
          )
          .toList(),
    );
  }
}
