// features/chat/providers/messages_provider.dart

final messagesProvider = StreamProvider.family<List<Message>, String>((ref, roomId) {
  final supabase = Supabase.instance.client;
  
  // 1) 초기 메시지 로드 + Realtime Broadcast 구독
  // 웹의 교랑톡과 동일한 채널명 사용 → 자동 동기화
  final channel = supabase.channel('room:$roomId');
  
  final controller = StreamController<List<Message>>();
  List<Message> messages = [];

  // 초기 로드
  supabase
    .from('messages')
    .select('*, sender:profiles(*)')
    .eq('room_id', roomId)
    .order('created_at')
    .then((data) {
      messages = data.map((e) => Message.fromJson(e)).toList();
      controller.add(messages);
    });

  // Broadcast 구독 (웹과 동일 채널)
  channel
    .onBroadcast(
      event: 'new_message',
      callback: (payload) {
        final msg = Message.fromJson(payload['message']);
        messages = [...messages, msg];
        controller.add(messages);
      },
    )
    .onBroadcast(
      event: 'message_deleted',
      callback: (payload) {
        messages = messages.map((m) =>
          m.id == payload['message_id']
            ? m.copyWith(isDeleted: true)
            : m
        ).toList();
        controller.add(messages);
      },
    )
    .subscribe();

  ref.onDispose(() {
    supabase.removeChannel(channel);
    controller.close();
  });

  return controller.stream;
});