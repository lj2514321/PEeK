import 'package:embyplayer/src/app/glass.dart';
import 'package:embyplayer/src/app/theme.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_scrobble_service.dart';
import 'package:embyplayer/src/features/scrobble/data/bangumi_store.dart';
import 'package:embyplayer/src/features/scrobble/domain/bangumi_profile.dart';
import 'package:flutter/material.dart';

class BangumiBindingSheet extends StatefulWidget {
  const BangumiBindingSheet({
    super.key,
    this.bangumiStore,
    this.bangumiService,
  });

  final BangumiStore? bangumiStore;
  final BangumiScrobbleService? bangumiService;

  @override
  State<BangumiBindingSheet> createState() => _BangumiBindingSheetState();
}

class _BangumiBindingSheetState extends State<BangumiBindingSheet> {
  late final BangumiStore _store = widget.bangumiStore ?? BangumiStore();
  late final BangumiScrobbleService _service =
      widget.bangumiService ?? BangumiScrobbleService();

  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _loading = true;
  bool _verifying = false;
  String? _errorMessage;
  BangumiProfile? _profile;

  @override
  void initState() {
    super.initState();
    _loadCurrentProfile();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentProfile() async {
    final profile = await _store.readProfile();
    if (mounted) {
      setState(() {
        _profile = profile;
        _loading = false;
      });
    }
  }

  Future<void> _verifyAndBind() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = '请输入 Bangumi 开发者 Access Token');
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    final verifiedProfile = await _service.verifyToken(token);
    if (!mounted) return;

    if (verifiedProfile != null) {
      await _store.saveProfile(verifiedProfile);
      setState(() {
        _profile = verifiedProfile;
        _verifying = false;
        _tokenController.clear();
      });
    } else {
      setState(() {
        _verifying = false;
        _errorMessage = '令牌校验失败，请检查 Token 有效性或网络连接';
      });
    }
  }

  Future<void> _toggleAutoScrobble(bool val) async {
    if (_profile == null) return;
    final updated = _profile!.copyWith(autoScrobble: val);
    await _store.saveProfile(updated);
    if (mounted) {
      setState(() => _profile = updated);
    }
  }

  Future<void> _unbind() async {
    await _store.clearProfile();
    if (mounted) {
      setState(() {
        _profile = null;
        _tokenController.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 500,
      padding: const EdgeInsets.all(24),
      decoration: AppGlass.decoration(radius: 24, elevated: true),
      child: _loading
          ? const SizedBox(
              height: 200,
              child: Center(
                child: CircularProgressIndicator(color: AppColors.spotlight),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 20),
                if (_profile != null)
                  _buildBoundState(context)
                else
                  _buildUnboundState(context),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF09199).withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.tv_rounded,
            color: Color(0xFFF09199),
            size: 22,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bangumi 番组计划联动',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '绑定后播放进度达到 80% 自动同步打卡标记已看',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white70),
          onPressed: () => Navigator.of(context).pop(_profile != null),
          splashRadius: 20,
        ),
      ],
    );
  }

  Widget _buildBoundState(BuildContext context) {
    final profile = _profile!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFF09199).withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFFF09199).withValues(alpha: 0.2),
                backgroundImage: profile.avatarUrl.isNotEmpty
                    ? NetworkImage(profile.avatarUrl)
                    : null,
                child: profile.avatarUrl.isEmpty
                    ? const Icon(Icons.person_rounded, color: Color(0xFFF09199))
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            profile.nickname,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '已连接',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppColors.success,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '@${profile.username} (UID: ${profile.userId})',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: _unbind,
                child: const Text('解除绑定', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.025),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '80% 进度自动静默打卡',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '播放动漫剧集达到 80% 或完播时，自动在 bgm.tv 标记该集为已看',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: profile.autoScrobble,
                activeThumbColor: const Color(0xFFF09199),
                onChanged: _toggleAutoScrobble,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUnboundState(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: Color(0xFFF09199),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '请前往 Bangumi 个人设置 - 开发者平台 (bgm.tv/dev/app) 创建应用并获取 Access Token 填入下方以完成绑定。',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary.withValues(alpha: 0.9),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _tokenController,
          obscureText: _obscureToken,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          decoration: InputDecoration(
            labelText: 'Personal Access Token',
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            hintText: '粘贴您的 Bangumi 访问令牌',
            hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
            prefixIcon: const Icon(Icons.key_rounded, color: Color(0xFFF09199)),
            suffixIcon: IconButton(
              icon: Icon(
                _obscureToken
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.white60,
                size: 18,
              ),
              onPressed: () => setState(() => _obscureToken = !_obscureToken),
            ),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFF09199), width: 1.5),
            ),
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          Text(
            _errorMessage!,
            style: const TextStyle(fontSize: 12, color: AppColors.error),
          ),
        ],
        const SizedBox(height: 20),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF09199),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _verifying ? null : _verifyAndBind,
          child: _verifying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  '验证并绑定账户',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
        ),
      ],
    );
  }
}
