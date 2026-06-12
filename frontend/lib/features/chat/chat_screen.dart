import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/meta_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/api/api_models.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.api,
    required this.character,
    required this.materials,
    required this.selectedMaterialIds,
  });

  final ApiClient api;
  final CharacterDto character;
  final List<MaterialDto> materials;
  final Set<String> selectedMaterialIds;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  List<_ChatEntry> _messages = _initialMessages();
  bool _pdfMode = false;
  bool _longReplyMode = false;
  bool _visualNovelMode = false;
  double _visualDialogueOpacity = 0.76;
  bool _loadingHistory = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id != widget.character.id) {
      _loadHistory();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final history = await widget.api.listChatMessages(
        characterId: widget.character.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _messages = history.isEmpty
            ? _initialMessages()
            : history
                .map(
                  (message) => _ChatEntry(
                    text: message.text,
                    role: _ChatRole.fromApiRole(message.role),
                  ),
                )
                .toList();
      });
      _scrollToBottom();
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loadingHistory = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedMaterials = widget.materials
        .where((material) => widget.selectedMaterialIds.contains(material.id))
        .toList();
    final hasMaterial = selectedMaterials.isNotEmpty;

    if (_visualNovelMode) {
      return _buildVisualNovelLayout(selectedMaterials, hasMaterial);
    }
    return _buildMessengerLayout(selectedMaterials, hasMaterial);
  }

  Widget _buildMessengerLayout(
    List<MaterialDto> selectedMaterials,
    bool hasMaterial,
  ) {
    final avatarUrl = widget.api.assetUrl(widget.character.baseImageUrl);
    return Column(
      children: [
        _buildHeader(hasMaterial: hasMaterial),
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: MetaSpacing.xl),
            children: [
              if (_error != null) _ErrorBanner(message: _error!),
              if (_pdfMode && hasMaterial)
                _ContextBanner(
                  title: 'PDF 모드',
                  text: selectedMaterials
                      .map((material) => material.title)
                      .join(', '),
                ),
              if (_loadingHistory)
                const _ContextBanner(
                  title: 'Chat',
                  text: '이전 대화를 불러오는 중',
                ),
              ..._messages.map((message) => _Bubble(
                    avatarUrl: avatarUrl,
                    text: message.text,
                    role: message.role,
                  )),
              if (_sending)
                _Bubble(
                  avatarUrl: avatarUrl,
                  text: '생각 중...',
                  role: _ChatRole.assistant,
                ),
            ],
          ),
        ),
        _buildComposer(),
      ],
    );
  }

  Widget _buildVisualNovelLayout(
    List<MaterialDto> selectedMaterials,
    bool hasMaterial,
  ) {
    final imageUrl = widget.api.assetUrl(
      widget.character.baseImageUrl ?? widget.character.visualNovelImageUrl,
    );
    final lastAssistant =
        _latestText(_ChatRole.assistant) ?? '자료를 올리면 먼저 훑어보고 어디부터 같이 볼지 물어볼게.';
    final lastUser = _latestText(_ChatRole.user);

    return Stack(
      children: [
        Positioned.fill(
          child: Image.network(
            imageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: MetaColors.inkDeep,
              child: Center(
                child: Icon(
                  Icons.person,
                  size: 120,
                  color: MetaColors.canvas,
                ),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  MetaColors.inkDeep.withValues(alpha: 0.08),
                  MetaColors.inkDeep.withValues(alpha: 0.02),
                  MetaColors.inkDeep.withValues(alpha: 0.76),
                ],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: _buildHeader(
            hasMaterial: hasMaterial,
            floating: true,
          ),
        ),
        if (_pdfMode && hasMaterial)
          Positioned(
            left: MetaSpacing.base,
            right: MetaSpacing.base,
            top: 96,
            child: _VisualModePill(
              icon: Icons.picture_as_pdf_outlined,
              text: selectedMaterials
                  .map((material) => material.title)
                  .join(', '),
            ),
          ),
        Positioned(
          left: MetaSpacing.base,
          right: MetaSpacing.base,
          top: _pdfMode && hasMaterial ? 142 : 96,
          child: _VisualOpacitySlider(
            value: _visualDialogueOpacity,
            onChanged: (value) => setState(
              () => _visualDialogueOpacity = value,
            ),
          ),
        ),
        Positioned(
          left: MetaSpacing.base,
          right: MetaSpacing.base,
          bottom: MetaSpacing.base,
          child: _VisualNovelDialoguePanel(
            characterName: widget.character.name,
            opacity: _visualDialogueOpacity,
            reply: _sending ? '(생각 중..)' : lastAssistant,
            userText: lastUser,
            composer: _buildComposer(visualMode: true),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader({required bool hasMaterial, bool floating = false}) {
    final textTheme = Theme.of(context).textTheme;
    final titleColor = floating ? MetaColors.canvas : MetaColors.inkDeep;

    return Padding(
      padding: EdgeInsets.all(floating ? MetaSpacing.base : MetaSpacing.xl),
      child: DecoratedBox(
        decoration: floating
            ? BoxDecoration(
                color: MetaColors.inkDeep.withValues(alpha: 0.48),
                border: Border.all(
                  color: MetaColors.canvas.withValues(alpha: 0.18),
                ),
                borderRadius: BorderRadius.circular(MetaRadii.xxl),
              )
            : const BoxDecoration(),
        child: Padding(
          padding: floating
              ? const EdgeInsets.symmetric(
                  horizontal: MetaSpacing.base,
                  vertical: MetaSpacing.md,
                )
              : EdgeInsets.zero,
          child: Wrap(
            spacing: MetaSpacing.xs,
            runSpacing: MetaSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: floating ? 96 : 120,
                child: Text(
                  'Chat',
                  style: textTheme.headlineMedium?.copyWith(color: titleColor),
                ),
              ),
              _ModeChip(
                label: 'Daily',
                selected: !_pdfMode,
                disabled: _sending,
                compact: floating,
                onTap: () => setState(() => _pdfMode = false),
              ),
              _ModeChip(
                label: 'PDF',
                selected: _pdfMode,
                disabled: !hasMaterial || _sending,
                compact: floating,
                onTap: hasMaterial
                    ? () => setState(() {
                          _pdfMode = true;
                          _longReplyMode = true;
                        })
                    : null,
              ),
              const SizedBox(width: MetaSpacing.xs),
              _ModeChip(
                label: '짧게',
                selected: !_longReplyMode,
                disabled: _sending,
                compact: floating,
                onTap: () => setState(() => _longReplyMode = false),
              ),
              _ModeChip(
                label: '길게',
                selected: _longReplyMode,
                disabled: _sending,
                compact: floating,
                onTap: () => setState(() => _longReplyMode = true),
              ),
              const SizedBox(width: MetaSpacing.xs),
              _ModeChip(
                label: '메신저',
                selected: !_visualNovelMode,
                disabled: _sending,
                compact: floating,
                onTap: () {
                  setState(() => _visualNovelMode = false);
                  _scrollToBottom();
                },
              ),
              _ModeChip(
                label: '비주얼',
                selected: _visualNovelMode,
                disabled: _sending,
                compact: floating,
                onTap: () => setState(() => _visualNovelMode = true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _latestText(_ChatRole role) {
    for (final message in _messages.reversed) {
      if (message.role == role && message.text.trim().isNotEmpty) {
        return message.text;
      }
    }
    return null;
  }

  Widget _buildComposer({bool visualMode = false}) {
    return Padding(
      padding: EdgeInsets.all(visualMode ? 0 : MetaSpacing.xl),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_sending,
              decoration: InputDecoration(
                hintText: _pdfMode ? 'PDF 내용에 대해 질문하기' : '캐릭터에게 말하기',
              ),
              onSubmitted: (_) {
                if (!_sending) {
                  _send();
                }
              },
            ),
          ),
          const SizedBox(width: MetaSpacing.md),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: const Icon(Icons.send),
            label: Text(visualMode ? '보내기' : 'Send'),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    if (_sending) {
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) {
      return;
    }
    _controller.clear();
    setState(() {
      _messages.add(_ChatEntry(text: text, role: _ChatRole.user));
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final response = await widget.api.sendChatMessage(
        characterId: widget.character.id,
        message: text,
        mode: _chatMode(),
        materialIds: _pdfMode
            ? widget.selectedMaterialIds.toList(growable: false)
            : const [],
      );
      setState(() {
        if (response.environmentBox.trim().isNotEmpty) {
          _messages.add(_ChatEntry(
            text: response.environmentBox,
            role: _ChatRole.environment,
          ));
        }
        _messages.add(_ChatEntry(
          text: response.reply,
          role: _ChatRole.assistant,
        ));
      });
      _scrollToBottom();
    } catch (error) {
      setState(() => _error = error.toString());
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  String _chatMode() {
    if (_pdfMode) {
      return _longReplyMode ? 'study_rag_chat' : 'study_rag_short_chat';
    }
    return _longReplyMode ? 'daily_long_chat' : 'daily_chat';
  }
}

List<_ChatEntry> _initialMessages() {
  return [
    const _ChatEntry(
      text: '자료를 올리면 먼저 훑어보고 어디부터 같이 볼지 물어볼게.',
      role: _ChatRole.assistant,
    ),
  ];
}

class _ChatEntry {
  const _ChatEntry({required this.text, required this.role});

  final String text;
  final _ChatRole role;
}

enum _ChatRole {
  user,
  assistant,
  environment;

  static _ChatRole fromApiRole(String role) {
    return switch (role) {
      'user' => _ChatRole.user,
      'environment' => _ChatRole.environment,
      _ => _ChatRole.assistant,
    };
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.selected,
    this.disabled = false,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(MetaRadii.full),
      onTap: disabled ? null : onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? MetaColors.inkDeep : MetaColors.canvas,
          border: Border.all(
            color: selected ? MetaColors.inkDeep : MetaColors.hairline,
          ),
          borderRadius: BorderRadius.circular(MetaRadii.full),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? MetaSpacing.md : MetaSpacing.base,
            vertical: compact ? 6 : MetaSpacing.xs,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontSize: compact ? 12 : null,
                  color: disabled
                      ? MetaColors.stone
                      : selected
                          ? MetaColors.canvas
                          : MetaColors.ink,
                ),
          ),
        ),
      ),
    );
  }
}

class _VisualModePill extends StatelessWidget {
  const _VisualModePill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: MetaColors.inkDeep.withValues(alpha: 0.58),
          border: Border.all(color: MetaColors.canvas.withValues(alpha: 0.16)),
          borderRadius: BorderRadius.circular(MetaRadii.full),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: MetaSpacing.base,
            vertical: MetaSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: MetaColors.canvas),
              const SizedBox(width: MetaSpacing.xs),
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: MetaColors.canvas,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VisualOpacitySlider extends StatelessWidget {
  const _VisualOpacitySlider({
    required this.value,
    required this.onChanged,
  });

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MetaColors.inkDeep.withValues(alpha: 0.42),
        border: Border.all(color: MetaColors.canvas.withValues(alpha: 0.16)),
        borderRadius: BorderRadius.circular(MetaRadii.full),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: MetaSpacing.base,
          vertical: 4,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.opacity,
              size: 16,
              color: MetaColors.canvas,
            ),
            const SizedBox(width: MetaSpacing.xs),
            Text(
              '창',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: MetaColors.canvas,
                  ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  value: value,
                  min: 0.36,
                  max: 0.92,
                  divisions: 14,
                  activeColor: MetaColors.canvas,
                  inactiveColor: MetaColors.canvas.withValues(alpha: 0.26),
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisualNovelDialoguePanel extends StatelessWidget {
  const _VisualNovelDialoguePanel({
    required this.characterName,
    required this.opacity,
    required this.reply,
    required this.composer,
    this.userText,
  });

  final String characterName;
  final double opacity;
  final String reply;
  final String? userText;
  final Widget composer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(MetaRadii.xxl),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: MetaColors.canvas.withValues(alpha: opacity),
            border:
                Border.all(color: MetaColors.canvas.withValues(alpha: 0.42)),
            borderRadius: BorderRadius.circular(MetaRadii.xxl),
            boxShadow: [
              BoxShadow(
                color: MetaColors.inkDeep.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(MetaSpacing.base),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: MetaColors.inkDeep,
                        borderRadius: BorderRadius.circular(MetaRadii.full),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: MetaSpacing.base,
                          vertical: MetaSpacing.xs,
                        ),
                        child: Text(
                          characterName,
                          style: textTheme.labelLarge?.copyWith(
                            color: MetaColors.canvas,
                          ),
                        ),
                      ),
                    ),
                    if (userText != null) ...[
                      const SizedBox(width: MetaSpacing.xs),
                      Expanded(
                        child: Text(
                          '나: $userText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: MetaSpacing.md),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Text(
                      reply,
                      style: textTheme.bodyLarge?.copyWith(
                        color: MetaColors.inkDeep,
                        height: 1.55,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: MetaSpacing.base),
                composer,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ContextBanner extends StatelessWidget {
  const _ContextBanner({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MetaSpacing.md),
      padding: const EdgeInsets.all(MetaSpacing.base),
      decoration: BoxDecoration(
        color: MetaColors.surfaceSoft,
        borderRadius: BorderRadius.circular(MetaRadii.xl),
      ),
      child:
          Text('$title · $text', style: Theme.of(context).textTheme.bodyMedium),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: MetaSpacing.md),
      padding: const EdgeInsets.all(MetaSpacing.base),
      decoration: BoxDecoration(
        color: MetaColors.critical.withValues(alpha: 0.08),
        border: Border.all(color: MetaColors.critical),
        borderRadius: BorderRadius.circular(MetaRadii.xl),
      ),
      child: Text(
        message,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: MetaColors.critical),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.avatarUrl,
    required this.text,
    required this.role,
  });

  final String avatarUrl;
  final String text;
  final _ChatRole role;

  @override
  Widget build(BuildContext context) {
    if (role == _ChatRole.environment) {
      return _EnvironmentBox(text: text);
    }
    final isUser = role == _ChatRole.user;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.only(bottom: MetaSpacing.md),
      padding: const EdgeInsets.all(MetaSpacing.base),
      decoration: BoxDecoration(
        color: isUser ? MetaColors.inkDeep : MetaColors.surfaceSoft,
        borderRadius: BorderRadius.circular(MetaRadii.xxl),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: isUser ? MetaColors.canvas : MetaColors.ink,
            ),
      ),
    );

    if (isUser) {
      return Align(alignment: Alignment.centerRight, child: bubble);
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipOval(
            child: Image.network(
              avatarUrl,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: MetaColors.surfaceSoft,
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.person, size: 20),
                ),
              ),
            ),
          ),
          const SizedBox(width: MetaSpacing.xs),
          Flexible(child: bubble),
        ],
      ),
    );
  }
}

class _EnvironmentBox extends StatelessWidget {
  const _EnvironmentBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: MetaSpacing.md),
        padding: const EdgeInsets.symmetric(
          horizontal: MetaSpacing.base,
          vertical: MetaSpacing.md,
        ),
        decoration: BoxDecoration(
          color: MetaColors.canvas,
          border: Border.all(color: MetaColors.hairlineSoft),
          borderRadius: BorderRadius.circular(MetaRadii.xl),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.auto_awesome, size: 18, color: MetaColors.steel),
            const SizedBox(width: MetaSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: MetaColors.steel,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
