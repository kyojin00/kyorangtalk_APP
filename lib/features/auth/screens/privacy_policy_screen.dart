import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
        title: Text('개인정보처리방침',
            style: TextStyle(
                color: AppTheme.textMain,
                fontWeight: FontWeight.w700,
                fontSize: 16)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: AppTheme.border),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '교랑톡 개인정보처리방침',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textMain,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '시행일자: 2026년 4월 23일',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSub,
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '교랑(이하 "회사")은 회원의 개인정보를 매우 중요시하며, 정보통신망 이용촉진 및 정보보호 등에 관한 법률 및 개인정보보호법을 준수하고 있습니다.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMain,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 32),

              _Section(
                title: '1. 수집하는 개인정보 항목',
                content: '''회사는 회원가입, 서비스 이용을 위해 다음과 같은 개인정보를 수집합니다.

[필수 항목]
• 이메일 주소 (이메일 가입 시)
• 전화번호 (전화번호 가입 시)
• 닉네임
• 생년월일
• 비밀번호 (이메일 가입 시, 암호화 저장)

[자동 수집 항목]
• 기기 정보 (OS 버전, 기기 모델명)
• IP 주소
• 서비스 이용 기록
• 접속 로그

[선택 항목]
• 프로필 사진
• 상태 메시지
• 마케팅 수신 동의''',
              ),

              _Section(
                title: '2. 개인정보 수집 및 이용 목적',
                content: '''회사는 수집한 개인정보를 다음의 목적으로 이용합니다.

[회원 관리]
• 회원제 서비스 이용에 따른 본인 확인
• 개인 식별, 불량 회원의 부정 이용 방지
• 가입 의사 확인, 연령 확인

[서비스 제공]
• 메신저 서비스 제공
• 친구 관리 및 채팅 기능
• 콘텐츠 제공
• 본인 인증

[마케팅 및 광고] (선택 동의 시)
• 이벤트 정보 및 참여기회 제공
• 광고성 정보 제공''',
              ),

              _Section(
                title: '3. 개인정보 보유 및 이용기간',
                content: '''① 회사는 원칙적으로 개인정보 수집 및 이용 목적이 달성된 후에는 해당 정보를 지체 없이 파기합니다.

② 단, 관련 법령에 의하여 보존할 필요가 있는 경우 다음과 같이 보존합니다.
   • 계약 또는 청약철회 등에 관한 기록: 5년
   • 대금결제 및 재화 등의 공급에 관한 기록: 5년
   • 소비자 불만 또는 분쟁처리에 관한 기록: 3년
   • 방문에 관한 기록: 3개월

③ 회원탈퇴 시 관련 정보는 즉시 파기됩니다.''',
              ),

              _Section(
                title: '4. 개인정보 제3자 제공',
                content: '''회사는 회원의 개인정보를 원칙적으로 외부에 제공하지 않습니다. 다만, 아래의 경우에는 예외로 합니다.

• 회원이 사전에 동의한 경우
• 법령의 규정에 의거하거나, 수사 목적으로 법령에 정해진 절차와 방법에 따라 수사기관의 요구가 있는 경우''',
              ),

              _Section(
                title: '5. 개인정보 처리위탁',
                content: '''회사는 원활한 서비스 제공을 위해 다음과 같이 개인정보 처리 업무를 외부 업체에 위탁하고 있습니다.

• Supabase (미국): 데이터베이스 호스팅
• Firebase (Google): 인증, 푸시 알림
• Resend: 이메일 발송

위탁 업체들은 개인정보를 안전하게 처리하도록 감독하고 있으며, 관련 법령을 준수합니다.''',
              ),

              _Section(
                title: '6. 개인정보의 파기절차 및 방법',
                content: '''① 파기절차
   • 회원이 입력한 정보는 목적 달성 후 별도의 DB에 옮겨져 내부 방침 및 법령에 따라 일정 기간 저장된 후 파기됩니다.

② 파기방법
   • 전자적 파일 형태: 복구할 수 없는 기술적 방법을 사용하여 삭제
   • 종이 문서: 분쇄기로 분쇄하거나 소각하여 파기''',
              ),

              _Section(
                title: '7. 회원의 권리',
                content: '''회원은 언제든지 다음과 같은 권리를 행사할 수 있습니다.

• 개인정보 열람 요구
• 개인정보 정정 요구
• 개인정보 삭제 요구
• 개인정보 처리 정지 요구

위 요청은 앱 내 설정 메뉴 또는 이메일(rywls123450@gmail.com)을 통해 가능합니다.''',
              ),

              _Section(
                title: '8. 개인정보의 안전성 확보 조치',
                content: '''회사는 개인정보의 안전성 확보를 위해 다음과 같은 조치를 취하고 있습니다.

• 비밀번호 암호화 저장
• 개인정보 접근 권한 최소화
• 보안 프로그램 설치 및 갱신
• 개인정보 처리시스템의 접근 제어
• 침해사고 대응을 위한 기술적 대책 마련''',
              ),

              _Section(
                title: '9. 쿠키 사용',
                content: '회사는 회원의 서비스 이용 분석을 위해 쿠키를 사용할 수 있으며, 회원은 브라우저 설정을 통해 쿠키 저장을 거부할 수 있습니다.',
              ),

              _Section(
                title: '10. 개인정보보호책임자',
                content: '''회사는 개인정보를 보호하고 개인정보와 관련한 불만을 처리하기 위하여 아래와 같이 관련 부서 및 개인정보보호책임자를 지정하고 있습니다.

개인정보보호책임자: 교진
이메일: rywls123450@gmail.com

개인정보 관련 문의사항은 위 연락처로 문의주시면 신속하고 성실하게 답변드리겠습니다.''',
              ),

              _Section(
                title: '11. 개인정보처리방침 변경',
                content: '본 개인정보처리방침이 변경되는 경우, 회사는 변경사항을 시행일자 7일 전부터 앱 내 공지사항을 통해 고지합니다.',
              ),

              const SizedBox(height: 20),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: AppTheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Text('개인정보 보호 문의',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                            )),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '이메일: rywls123450@gmail.com\n\n개인정보와 관련된 문의, 불만처리 등 제반 사항을 담당 부서에서 신속하고 성실하게 답변 드리고 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSub,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String content;

  const _Section({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            content,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textMain,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }
}