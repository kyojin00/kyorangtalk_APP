import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

enum PolicyType { privacy, terms }

class PolicyScreen extends StatelessWidget {
  final PolicyType type;

  const PolicyScreen({super.key, required this.type});

  String get _title =>
      type == PolicyType.privacy ? '개인정보 처리방침' : '이용약관';

  String get _content =>
      type == PolicyType.privacy ? _privacyText : _termsText;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: AppTheme.primaryLight, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_title,
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.update,
                      color: AppTheme.textSub, size: 14),
                  const SizedBox(width: 6),
                  Text('최종 업데이트: 2026.04.21',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSub)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              _content,
              style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textMain,
                  height: 1.7),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

const String _privacyText = '''
교랑톡(이하 "서비스")은 이용자의 개인정보를 중요시하며, 「개인정보 보호법」을 준수하고 있습니다.

■ 1. 수집하는 개인정보 항목

서비스는 회원가입, 서비스 이용을 위해 다음의 개인정보를 수집합니다.

[필수 항목]
• 이메일 주소 또는 전화번호
• 비밀번호 (암호화 저장)
• 닉네임
• 프로필 사진 (선택)

[자동 수집 항목]
• 기기정보 (OS, 앱 버전)
• 접속 로그, IP 주소
• 푸시 알림 토큰 (FCM)

■ 2. 개인정보의 수집 및 이용 목적

• 회원 식별 및 본인 확인
• 서비스 제공 및 운영
• 친구 추가, 메시지 전송 등 서비스 기능 제공
• 부정 이용 방지 및 분쟁 조정
• 고객 문의 응대

■ 3. 개인정보의 보유 및 이용기간

이용자의 개인정보는 회원 탈퇴 시까지 보유합니다. 다만, 관계 법령에 따라 일정 기간 보관이 필요한 경우 그 기간 동안 보관합니다.

• 통신비밀보호법: 접속 로그 3개월
• 전자상거래법: 계약/청약철회 기록 5년
• 회원 탈퇴 후 30일 이내 개인정보 완전 삭제

■ 4. 개인정보의 제3자 제공

서비스는 이용자의 개인정보를 원칙적으로 제3자에게 제공하지 않습니다. 다만, 다음의 경우는 예외입니다.

• 이용자가 사전에 동의한 경우
• 법령의 규정에 의거하거나, 수사 목적으로 수사기관의 요구가 있는 경우

■ 5. 개인정보의 처리 위탁

서비스는 원활한 서비스 제공을 위해 다음과 같이 개인정보 처리를 위탁합니다.

• 클라우드 서비스: Supabase (데이터 저장)
• 푸시 알림: Firebase Cloud Messaging
• 인증 서비스: Firebase Authentication, Google OAuth

■ 6. 이용자의 권리와 행사 방법

이용자는 언제든지 다음의 권리를 행사할 수 있습니다.

• 개인정보 열람 요구
• 오류 정정 요구
• 삭제 요구
• 처리 정지 요구

요청은 설정 > 문의하기를 통해 접수할 수 있습니다.

■ 7. 개인정보의 파기

회원 탈퇴 시 이용자의 개인정보는 즉시 파기됩니다.

• 전자적 파일: 복구 불가능한 방법으로 영구 삭제
• 종이 문서: 분쇄 또는 소각

■ 8. 개인정보 보호 책임자

• 담당자: 교랑톡 운영팀
• 이메일: rywls123450@gmail.com

이용자는 서비스를 이용하며 발생하는 모든 개인정보보호 관련 문의, 불만처리, 피해구제 등에 관한 사항을 위 담당자에게 문의하실 수 있습니다.

■ 9. 개인정보 처리방침의 변경

이 개인정보 처리방침은 법령 및 방침에 따른 변경내용의 추가, 삭제 및 정정이 있을 경우 변경사항을 앱 내 공지사항을 통해 고지할 것입니다.
''';

const String _termsText = '''
교랑톡(이하 "서비스")의 이용약관에 오신 것을 환영합니다.

■ 제1조 (목적)

이 약관은 교랑톡(이하 "회사")이 제공하는 서비스의 이용과 관련하여 회사와 이용자 간의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.

■ 제2조 (정의)

1. "서비스"란 회사가 제공하는 메신저 및 관련 부가 서비스를 의미합니다.
2. "이용자"란 이 약관에 따라 서비스를 이용하는 회원을 말합니다.
3. "콘텐츠"란 이용자가 서비스 내에서 작성, 업로드하는 모든 게시물, 메시지, 이미지 등을 의미합니다.

■ 제3조 (약관의 효력 및 변경)

1. 이 약관은 서비스 화면에 게시하거나 기타 방법으로 이용자에게 공지함으로써 효력을 발생합니다.
2. 회사는 필요한 경우 약관을 변경할 수 있으며, 변경 시 사전에 공지합니다.
3. 변경된 약관에 동의하지 않을 경우 이용자는 서비스 이용을 중단하고 탈퇴할 수 있습니다.

■ 제4조 (회원 가입)

1. 이용자는 회사가 정한 가입 양식에 따라 회원정보를 기입한 후 이 약관에 동의함으로써 회원가입을 신청합니다.
2. 회사는 다음의 경우 회원가입을 거절할 수 있습니다.
  • 타인의 정보를 도용한 경우
  • 허위 정보를 기재한 경우
  • 기타 회사가 정한 이용신청요건이 미비한 경우

■ 제5조 (서비스의 이용)

1. 서비스 이용은 회사의 업무상 또는 기술상 특별한 지장이 없는 한 연중무휴, 1일 24시간 제공을 원칙으로 합니다.
2. 회사는 다음 각 호에 해당하는 경우 서비스 제공을 중단할 수 있습니다.
  • 시스템 점검, 보수, 교체가 필요한 경우
  • 정전, 통신장애 등 불가항력적 사유가 발생한 경우
  • 기타 불가피한 사유가 있는 경우

■ 제6조 (이용자의 의무)

이용자는 다음 행위를 해서는 안 됩니다.

• 타인의 개인정보를 무단으로 수집, 저장, 공개하는 행위
• 음란물, 폭력적인 내용, 혐오 표현 등 공서양속에 반하는 콘텐츠를 게시하는 행위
• 스팸, 광고성 메시지를 무단으로 전송하는 행위
• 타인을 사칭하거나 허위 정보를 유포하는 행위
• 서비스의 안정적 운영을 방해하는 행위
• 기타 관계 법령에 위반되는 행위

■ 제7조 (저작권 및 콘텐츠 관리)

1. 이용자가 서비스 내에 게시한 콘텐츠의 저작권은 이용자에게 귀속됩니다.
2. 이용자는 게시한 콘텐츠가 제3자의 권리를 침해하지 않음을 보증합니다.
3. 회사는 다음의 경우 이용자의 콘텐츠를 사전 통지 없이 삭제할 수 있습니다.
  • 관계 법령에 위반되는 경우
  • 다른 이용자 또는 제3자의 권리를 침해하는 경우
  • 이 약관에 위배되는 경우

■ 제8조 (계정 정지 및 탈퇴)

1. 이용자가 이 약관을 위반한 경우, 회사는 경고, 일시정지, 영구정지 등의 조치를 취할 수 있습니다.
2. 이용자는 언제든지 설정 > 계정 탈퇴를 통해 서비스 이용을 중단할 수 있습니다.

■ 제9조 (책임의 제한)

1. 회사는 천재지변, 전쟁, 기타 불가항력으로 인하여 서비스를 제공할 수 없는 경우 책임을 지지 않습니다.
2. 회사는 이용자 간 또는 이용자와 제3자 간 분쟁에 대해 개입할 의무가 없으며, 이로 인한 손해를 배상할 책임이 없습니다.
3. 회사는 이용자가 게시한 콘텐츠의 신뢰도, 정확성에 대해 책임지지 않습니다.

■ 제10조 (분쟁 해결)

1. 회사와 이용자 간의 분쟁은 상호 협의하여 해결함을 원칙으로 합니다.
2. 협의가 이루어지지 않을 경우, 관련 법령 및 일반 상관례에 따릅니다.

■ 제11조 (준거법 및 관할)

이 약관에 따른 분쟁은 대한민국 법령에 의해 규율되며, 관할 법원은 민사소송법에 따릅니다.

■ 부칙

이 약관은 2026년 4월 21일부터 시행됩니다.

문의: rywls123450@gmail.com
''';