import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

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
        title: Text('이용약관',
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
                '교랑톡 서비스 이용약관',
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
              const SizedBox(height: 32),

              _Section(
                title: '제1조 (목적)',
                content: '본 약관은 교랑(이하 "회사")가 제공하는 교랑톡 서비스(이하 "서비스")의 이용과 관련하여 회사와 이용자의 권리, 의무 및 책임사항, 기타 필요한 사항을 규정함을 목적으로 합니다.',
              ),

              _Section(
                title: '제2조 (용어의 정의)',
                content: '''① "서비스"란 회사가 제공하는 교랑톡 메신저 서비스를 말합니다.
② "이용자"란 서비스에 접속하여 본 약관에 따라 회사가 제공하는 서비스를 받는 회원을 말합니다.
③ "회원"이란 서비스에 회원가입을 한 자로서, 계속적으로 회사가 제공하는 서비스를 이용할 수 있는 자를 말합니다.''',
              ),

              _Section(
                title: '제3조 (약관의 효력 및 변경)',
                content: '''① 본 약관은 서비스를 이용하고자 하는 모든 이용자에 대하여 그 효력이 발생합니다.
② 회사는 필요한 경우 관련 법령을 위배하지 않는 범위 내에서 본 약관을 변경할 수 있습니다.
③ 약관이 변경되는 경우 회사는 변경사항을 시행일자 7일 전부터 공지합니다.''',
              ),

              _Section(
                title: '제4조 (회원가입)',
                content: '''① 이용자는 회사가 정한 가입 양식에 따라 회원정보를 기입한 후 본 약관에 동의한다는 의사표시를 함으로써 회원가입을 신청합니다.
② 회사는 다음 각 호에 해당하는 신청에 대해서는 승낙하지 않을 수 있습니다.
   - 타인의 명의를 이용한 경우
   - 회원가입 사항을 허위로 기재한 경우
   - 만 14세 미만인 경우 (법정대리인 동의 필요)
   - 기타 회사가 정한 이용신청 요건에 미비한 경우''',
              ),

              _Section(
                title: '제5조 (서비스의 제공)',
                content: '''① 회사는 회원에게 다음과 같은 서비스를 제공합니다.
   - 1:1 채팅 서비스
   - 그룹 채팅 서비스
   - 오픈 채팅 서비스
   - 친구 관리 서비스
   - 기타 회사가 추가로 개발하거나 제공하는 서비스
② 서비스는 연중무휴, 1일 24시간 제공함을 원칙으로 합니다.
③ 시스템 점검, 장애 등의 이유로 서비스 제공이 일시 중단될 수 있습니다.''',
              ),

              _Section(
                title: '제6조 (회원의 의무)',
                content: '''① 회원은 다음 행위를 하여서는 안 됩니다.
   - 타인의 정보 도용
   - 회사가 게시한 정보의 변경
   - 회사가 정한 정보 외의 정보 송신 또는 게시
   - 타인의 명예를 손상시키거나 불이익을 주는 행위
   - 음란물, 폭력물 등 반사회적 정보의 유포
   - 영리 목적의 광고성 정보 전송
   - 해킹, 크래킹 등 서비스를 방해하는 행위''',
              ),

              _Section(
                title: '제7조 (서비스 이용의 제한)',
                content: '''회사는 회원이 다음 각 호에 해당하는 경우 서비스 이용을 제한하거나 계정을 영구 정지할 수 있습니다.
- 본 약관을 위반한 경우
- 타인의 권리를 침해한 경우
- 서비스의 정상적인 운영을 방해한 경우
- 관련 법령을 위반한 경우''',
              ),

              _Section(
                title: '제8조 (계약 해지)',
                content: '''① 회원은 언제든지 서비스 내 설정 메뉴를 통해 회원탈퇴를 신청할 수 있으며, 회사는 즉시 이를 처리합니다.
② 회원탈퇴 시 회원의 모든 데이터는 삭제되며, 복구할 수 없습니다.
③ 단, 관련 법령에 따라 보존해야 하는 정보는 일정 기간 보관됩니다.''',
              ),

              _Section(
                title: '제9조 (면책조항)',
                content: '''① 회사는 천재지변 또는 이에 준하는 불가항력으로 인하여 서비스를 제공할 수 없는 경우에는 서비스 제공에 관한 책임이 면제됩니다.
② 회사는 회원의 귀책사유로 인한 서비스 이용의 장애에 대하여 책임을 지지 않습니다.
③ 회사는 회원이 서비스를 이용하여 기대하는 수익을 상실한 것에 대하여 책임을 지지 않습니다.''',
              ),

              _Section(
                title: '제10조 (관할 법원)',
                content: '본 약관에 관한 분쟁은 대한민국법을 적용하며, 회사와 회원 간에 발생한 분쟁에 대한 소송의 관할 법원은 민사소송법상의 관할 법원으로 합니다.',
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
                        Icon(Icons.info_outline,
                            color: AppTheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Text('문의처',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textMain,
                            )),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '교랑\n이메일: rywls123450@gmail.com',
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