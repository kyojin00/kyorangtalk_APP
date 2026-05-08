import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'room_gallery_screen.dart';
import 'room_memory_screen.dart';

// ═══════════════════════════════════════════════════
// 📑 채팅방 더보기 시트 (갤러리 / 추억 진입)
// ═══════════════════════════════════════════════════
//
// 사용:
//   showRoomMoreSheet(
//     context,
//     roomId: widget.room.roomId,
//     isGroup: false,
//     roomName: widget.room.partnerName,
//     myId: _myId,
//     partnerId: widget.room.partnerId,           // DM에서만 의미 있음
//     partnerName: widget.room.partnerName,       // DM에서만
//   );
//
// 그룹은 partnerId/partnerName을 안 넘기면 화면에서 세그먼트가 자동으로 숨음.
// ═══════════════════════════════════════════════════

Future<void> showRoomMoreSheet(
  BuildContext context, {
  required String roomId,
  required bool isGroup,
  required String roomName,
  required String myId,
  String? partnerId,
  String? partnerName,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppTheme.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.photo_library_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            title: Text(
              '갤러리',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              '주고받은 사진 · 파일 · 링크',
              style: TextStyle(color: AppTheme.textSub, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoomGalleryScreen(
                    roomId: roomId,
                    isGroup: isGroup,
                    roomName: roomName,
                    myId: myId,
                    partnerId: partnerId,
                    partnerName: partnerName,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppTheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.favorite_outline,
                  color: AppTheme.primary, size: 20),
            ),
            title: Text(
              '추억',
              style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              '함께한 시간과 통계',
              style: TextStyle(color: AppTheme.textSub, fontSize: 12),
            ),
            onTap: () {
              Navigator.pop(sheetCtx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoomMemoryScreen(
                    roomId: roomId,
                    isGroup: isGroup,
                    roomName: roomName,
                    myId: myId,
                    partnerId: partnerId,
                    partnerName: partnerName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}