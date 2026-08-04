import 'package:flutter/material.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart' show Int64;

import '../game/palette.dart';
import '../spacetime/generated/player_character.dart';
import 'cyborg_kind.dart';
import 'cyborg_portrait.dart';
import 'cyborg_session.dart';
import 'ui_kit.dart';

/// 캐릭터를 고르거나 새로 만드는 화면.
///
/// 캐릭터가 하나도 없으면 만들기 화면으로 시작한다. 빈 목록을 보여 준 뒤
/// "만들기" 를 누르게 하는 단계는 아무 정보도 주지 않는다.
class CharacterSelectScreen extends StatefulWidget {
  const CharacterSelectScreen({
    super.key,
    required this.session,
    required this.onStart,
  });

  final CyborgSession session;

  /// 고른 캐릭터로 게임을 시작할 때 부른다.
  final void Function(PlayerCharacter character) onStart;

  @override
  State<CharacterSelectScreen> createState() => _CharacterSelectScreenState();
}

class _CharacterSelectScreenState extends State<CharacterSelectScreen> {
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final characters = session.characters;

    // 캐릭터가 없으면 만들기 화면 외에 보여 줄 것이 없다.
    final showCreate = _creating || characters.isEmpty;

    return CyborgBackdrop(
      child: showCreate
          ? _CreateCharacterView(
              session: session,
              // 첫 캐릭터를 만드는 중이라면 돌아갈 목록이 없다.
              onCancel: characters.isEmpty
                  ? null
                  : () => setState(() => _creating = false),
              onCreated: () => setState(() => _creating = false),
            )
          : _CharacterListView(
              session: session,
              onStart: widget.onStart,
              onCreateNew: () => setState(() => _creating = true),
            ),
    );
  }
}

// ── 목록 ────────────────────────────────────────────────────────────────

class _CharacterListView extends StatelessWidget {
  const _CharacterListView({
    required this.session,
    required this.onStart,
    required this.onCreateNew,
  });

  final CyborgSession session;
  final void Function(PlayerCharacter character) onStart;
  final VoidCallback onCreateNew;

  static const int _maxCharacters = 4;

  @override
  Widget build(BuildContext context) {
    final characters = session.characters;
    final selected = session.selectedCharacter;

    return CyborgCenter(
      maxWidth: 560,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: CyborgHeading(
                  title: '요원 선택',
                  subtitle: '출격할 사이보그를 고른다.',
                ),
              ),
              _AccountMenu(session: session),
            ],
          ),
          const SizedBox(height: 24),

          // 카드가 한 줄에 두 개씩 들어가되, 좁은 화면에서는 한 개로 접힌다.
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 380 ? 1 : 2;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.78,
                children: [
                  for (final character in characters)
                    _CharacterCard(
                      character: character,
                      selected: selected?.id == character.id,
                      busy: session.busy,
                      onTap: () => session.selectCharacter(character.id),
                      onDelete: () => _confirmDelete(context, character),
                    ),
                  if (characters.length < _maxCharacters)
                    _AddCharacterCard(onTap: session.busy ? null : onCreateNew),
                ],
              );
            },
          ),

          CyborgError(message: session.error),
          const SizedBox(height: 24),

          CyborgButton(
            label: selected == null ? '캐릭터를 고르시오' : '출격',
            busy: session.busy,
            accent: selected == null
                ? GamePalette.textDim
                : CyborgKind.fromId(selected.kind).accent,
            onPressed: selected == null ? null : () => onStart(selected),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PlayerCharacter character,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF141A24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: GamePalette.floorHazardGlow.withValues(alpha: 0.4),
          ),
        ),
        title: const Text(
          '캐릭터 삭제',
          style: TextStyle(color: GamePalette.textPrimary, fontSize: 17),
        ),
        content: Text(
          '"${character.name}" 을(를) 지운다. 되돌릴 수 없다.',
          style: const TextStyle(color: GamePalette.textDim, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(foregroundColor: GamePalette.textDim),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: GamePalette.floorHazardGlow,
            ),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await session.deleteCharacter(character.id);
    }
  }
}

/// 캐릭터 한 명을 보여 주는 카드.
class _CharacterCard extends StatelessWidget {
  const _CharacterCard({
    required this.character,
    required this.selected,
    required this.busy,
    required this.onTap,
    required this.onDelete,
  });

  final PlayerCharacter character;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final kind = CyborgKind.fromId(character.kind);

    return GestureDetector(
      onTap: busy ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? kind.accent.withValues(alpha: 0.08)
              : GamePalette.hudBackground,
          border: Border.all(
            color: selected
                ? kind.accent
                : GamePalette.floorGrid.withValues(alpha: 0.8),
            width: selected ? 1.8 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 14, 10, 4),
                    child: CyborgPortrait(kind: kind, selected: selected),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: Column(
                    children: [
                      Text(
                        character.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected
                              ? GamePalette.textPrimary
                              : GamePalette.textDim,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Lv.${character.level} · ${kind.codename}',
                        style: TextStyle(
                          color: selected
                              ? kind.accent
                              : GamePalette.textDim.withValues(alpha: 0.7),
                          fontSize: 11,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 삭제는 선택된 카드에서만 열어 둔다. 모든 카드에 X 를 띄우면
            // 고르려다 지우는 사고가 난다.
            if (selected)
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  onPressed: busy ? null : onDelete,
                  icon: const Icon(Icons.close_rounded, size: 17),
                  color: GamePalette.textDim,
                  tooltip: '삭제',
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 캐릭터를 새로 만드는 빈 카드.
class _AddCharacterCard extends StatelessWidget {
  const _AddCharacterCard({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            color: GamePalette.floorGrid,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, color: GamePalette.textDim, size: 30),
              SizedBox(height: 8),
              Text(
                '새 캐릭터',
                style: TextStyle(color: GamePalette.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 계정 메뉴(로그아웃).
class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.session});

  final CyborgSession session;

  @override
  Widget build(BuildContext context) {
    final email = session.account?.email ?? '';

    return PopupMenuButton<String>(
      enabled: !session.busy,
      color: const Color(0xFF141A24),
      icon: const Icon(Icons.account_circle_outlined,
          color: GamePalette.textDim),
      tooltip: email,
      onSelected: (value) {
        if (value == 'logout') session.logout();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            email,
            style: const TextStyle(color: GamePalette.textDim, fontSize: 12),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'logout',
          child: Text(
            '로그아웃',
            style: TextStyle(color: GamePalette.textPrimary, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

// ── 만들기 ──────────────────────────────────────────────────────────────

class _CreateCharacterView extends StatefulWidget {
  const _CreateCharacterView({
    required this.session,
    required this.onCancel,
    required this.onCreated,
  });

  final CyborgSession session;

  /// 목록으로 돌아간다. 첫 캐릭터를 만드는 중이면 null(돌아갈 곳이 없다).
  final VoidCallback? onCancel;

  final VoidCallback onCreated;

  @override
  State<_CreateCharacterView> createState() => _CreateCharacterViewState();
}

class _CreateCharacterViewState extends State<_CreateCharacterView> {
  final _name = TextEditingController();
  CyborgKind _kind = CyborgKind.male;
  String? _localError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _localError = '이름은 2자 이상이다.');
      return;
    }
    setState(() => _localError = null);

    final ok = await widget.session.createCharacter(
      name: name,
      kind: _kind.id,
    );
    if (ok && mounted) widget.onCreated();
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.busy;

    return CyborgCenter(
      maxWidth: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (widget.onCancel != null)
                IconButton(
                  onPressed: busy ? null : widget.onCancel,
                  icon: const Icon(Icons.arrow_back),
                  color: GamePalette.textDim,
                  tooltip: '목록으로',
                ),
              const Expanded(
                child: CyborgHeading(
                  title: '요원 등록',
                  subtitle: '몸을 고르고 호출 부호를 정한다.',
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 두 외형을 나란히 놓고 실루엣을 직접 비교하게 한다.
          SizedBox(
            height: 260,
            child: Row(
              children: [
                for (final kind in CyborgKind.values) ...[
                  Expanded(
                    child: _KindOption(
                      kind: kind,
                      selected: _kind == kind,
                      onTap: busy ? null : () => setState(() => _kind = kind),
                    ),
                  ),
                  if (kind != CyborgKind.values.last) const SizedBox(width: 12),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            _kind.tagline,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: GamePalette.textDim,
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          CyborgField(
            controller: _name,
            label: '호출 부호',
            hint: '2~16자',
            enabled: !busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
          ),

          CyborgError(message: _localError ?? widget.session.error),
          const SizedBox(height: 22),

          CyborgButton(
            label: '등록',
            busy: busy,
            accent: _kind.accent,
            onPressed: _create,
          ),
        ],
      ),
    );
  }
}

/// 만들기 화면의 외형 선택 칸.
class _KindOption extends StatelessWidget {
  const _KindOption({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final CyborgKind kind;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected
              ? kind.accent.withValues(alpha: 0.08)
              : GamePalette.hudBackground,
          border: Border.all(
            color: selected ? kind.accent : GamePalette.floorGrid,
            width: selected ? 1.8 : 1,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                child: CyborgPortrait(kind: kind, selected: selected),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Column(
                children: [
                  Text(
                    kind.codename,
                    style: TextStyle(
                      color: selected ? kind.accent : GamePalette.textDim,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    kind.label,
                    style: TextStyle(
                      color: selected
                          ? GamePalette.textPrimary
                          : GamePalette.textDim.withValues(alpha: 0.7),
                      fontSize: 12,
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
}

/// 목록 화면에서 쓰는 식별자 타입을 밖으로 노출한다.
///
/// 화면 코드가 `spacetimedb_sdk` 를 직접 import 하지 않도록 하는 얇은 통로다.
typedef CharacterId = Int64;
