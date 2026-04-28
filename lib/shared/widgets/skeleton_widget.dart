import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: AppTheme.border.withOpacity(_animation.value),
          borderRadius: BorderRadius.circular(widget.borderRadius),
        ),
      ),
    );
  }
}

class ChatListSkeleton extends StatelessWidget {
  const ChatListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 8,
      itemBuilder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            const SkeletonBox(
                width: 50, height: 50, borderRadius: 25),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(
                          width: 80 + (__ % 3) * 20.0,
                          height: 14),
                      const Spacer(),
                      const SkeletonBox(width: 36, height: 10),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SkeletonBox(
                      width: 140 + (__ % 4) * 20.0, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FriendListSkeleton extends StatelessWidget {
  const FriendListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            const SkeletonBox(
                width: 46, height: 46, borderRadius: 23),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                      width: 70 + (i % 3) * 25.0, height: 14),
                  const SizedBox(height: 6),
                  SkeletonBox(
                      width: 110 + (i % 4) * 15.0, height: 10),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const SkeletonBox(
                width: 36, height: 36, borderRadius: 10),
          ],
        ),
      ),
    );
  }
}

class MessageSkeleton extends StatelessWidget {
  const MessageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 12),
      itemCount: 8,
      itemBuilder: (_, i) {
        final isMe = i % 3 == 0;
        final width = 100.0 + (i % 5) * 30.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                const SkeletonBox(
                    width: 28, height: 28, borderRadius: 14),
                const SizedBox(width: 6),
              ],
              SkeletonBox(
                  width: width,
                  height: 38,
                  borderRadius: 18),
            ],
          ),
        );
      },
    );
  }
}

class GroupListSkeleton extends StatelessWidget {
  const GroupListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, i) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          border:
              Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            const SkeletonBox(
                width: 50, height: 50, borderRadius: 25),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonBox(
                          width: 90 + (i % 3) * 20.0,
                          height: 14),
                      const Spacer(),
                      const SkeletonBox(width: 28, height: 10),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SkeletonBox(
                      width: 130 + (i % 4) * 15.0, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ProfileSkeleton extends StatelessWidget {
  const ProfileSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          const SkeletonBox(width: 88, height: 88, borderRadius: 44),
          const SizedBox(height: 16),
          const SkeletonBox(width: 120, height: 22),
          const SizedBox(height: 8),
          const SkeletonBox(width: 160, height: 14),
          const SizedBox(height: 24),
          const SkeletonBox(
              width: double.infinity, height: 48, borderRadius: 12),
          const SizedBox(height: 32),
          Divider(color: AppTheme.border),
          const SizedBox(height: 8),
          ...List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16),
                child: Row(
                  children: [
                    const SkeletonBox(
                        width: 20, height: 20, borderRadius: 4),
                    const SizedBox(width: 12),
                    SkeletonBox(
                        width: 80 + i * 20.0, height: 14),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}