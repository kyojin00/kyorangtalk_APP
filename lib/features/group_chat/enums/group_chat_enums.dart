import 'package:flutter/material.dart';

// ═══════════════════════════════════════════════════
// 그룹 채팅 enum + 상수
//
// 위치: lib/features/group_chat/enums/group_chat_enums.dart
// ═══════════════════════════════════════════════════

const openCategories = [
  '전체', '일반', '게임', '공부', '취미', '운동', '음악', '여행', '기타'
];

const createCategories = [
  '일반', '게임', '공부', '취미', '운동', '음악', '여행', '기타'
];

// ─── 오픈채팅 정렬 ─────────────────────────────────
enum OpenRoomSort {
  popular,
  members,
  recent,
}

extension OpenRoomSortLabel on OpenRoomSort {
  String get label {
    switch (this) {
      case OpenRoomSort.popular: return '인기순';
      case OpenRoomSort.members: return '사람수';
      case OpenRoomSort.recent:  return '최신순';
    }
  }

  IconData get icon {
    switch (this) {
      case OpenRoomSort.popular: return Icons.favorite_rounded;
      case OpenRoomSort.members: return Icons.people_rounded;
      case OpenRoomSort.recent:  return Icons.access_time_rounded;
    }
  }
}

// ─── 내 채팅방 필터 ────────────────────────────────
enum MyRoomFilter { all, group, open }

extension MyRoomFilterLabel on MyRoomFilter {
  String get label {
    switch (this) {
      case MyRoomFilter.all:   return '전체';
      case MyRoomFilter.group: return '그룹';
      case MyRoomFilter.open:  return '오픈';
    }
  }
}