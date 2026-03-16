const { chromium } = require('playwright');

const URL = 'https://evote.ksd.or.kr/login';

async function runTests() {
  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({
    locale: 'ko-KR',
    userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36',
  });
  const page = await context.newPage();
  const results = [];

  async function test(section, name, fn) {
    try {
      await fn();
      results.push({ section, name, status: 'pass' });
      console.log(`  ✅ PASS  ${name}`);
    } catch (e) {
      results.push({ section, name, status: 'fail', error: e.message });
      console.log(`  ❌ FAIL  ${name}`);
      console.log(`           ${e.message}`);
    }
  }

  await page.goto(URL, { waitUntil: 'networkidle', timeout: 20000 });

  // ── 페이지 로드 ───────────────────────────────────────────
  console.log('\n📌 페이지 로드');

  await test('페이지 로드', '페이지가 정상 로드된다', async () => {
    if (!page.url().includes('evote.ksd.or.kr')) throw new Error(`URL: ${page.url()}`);
    console.log(`           → URL: ${page.url()}`);
  });

  await test('페이지 로드', '타이틀이 "K-VOTE"를 포함한다', async () => {
    const title = await page.title();
    if (!title.includes('K-VOTE')) throw new Error(`타이틀: "${title}"`);
    console.log(`           → "${title}"`);
  });

  // ── 매뉴얼 안내 모달 ──────────────────────────────────────
  console.log('\n📌 매뉴얼 안내 모달');

  await test('매뉴얼 모달', '"K-VOTE 이용 전 매뉴얼을 참고하세요!" 문구가 표시된다', async () => {
    const el = page.locator('text=K-VOTE 이용 전 매뉴얼을 참고하세요').first();
    if (!await el.isVisible()) throw new Error('매뉴얼 안내 문구 없음');
  });

  await test('매뉴얼 모달', '"발행회사용 매뉴얼 다운받기" 버튼이 존재한다', async () => {
    const el = page.locator('button:has-text("발행회사용 매뉴얼 다운받기")').first();
    if (!await el.isVisible()) throw new Error('버튼 없음');
  });

  await test('매뉴얼 모달', '"주주용 매뉴얼(PC)" 버튼이 존재한다', async () => {
    const el = page.locator('button:has-text("주주용 매뉴얼(PC)")').first();
    if (!await el.isVisible()) throw new Error('버튼 없음');
  });

  await test('매뉴얼 모달', '"기관투자자용 매뉴얼 다운받기" 버튼이 존재한다', async () => {
    const el = page.locator('button:has-text("기관투자자용 매뉴얼 다운받기")').first();
    if (!await el.isVisible()) throw new Error('버튼 없음');
  });

  await test('매뉴얼 모달', '"확인" 버튼이 존재한다', async () => {
    const el = page.locator('.ant-modal button:has-text("확인")').first();
    if (!await el.isVisible()) throw new Error('"확인" 버튼 없음');
  });

  // 모달 닫기 ("확인" 클릭)
  await page.locator('.ant-modal button:has-text("확인")').first().click();
  await page.waitForTimeout(600);
  console.log('  ℹ  "확인" 클릭으로 모달 닫음');

  // ── 공지 팝업 ─────────────────────────────────────────────
  console.log('\n📌 공지 팝업');

  await test('공지 팝업', '공지 내용이 표시된다', async () => {
    const el = page.locator('text=오늘 하루 열지 않기').first();
    if (!await el.isVisible()) throw new Error('공지 팝업 없음');
  });

  // "오늘 하루 열지 않기" 클릭
  await page.locator('text=오늘 하루 열지 않기').first().click();
  await page.waitForTimeout(600);
  console.log('  ℹ  공지 팝업 닫음');

  // ── 사이드 네비게이션 ─────────────────────────────────────
  console.log('\n📌 사이드 네비게이션');

  await test('사이드 네비게이션', '"공지사항" 메뉴가 존재한다', async () => {
    const el = page.locator('.ant-drawer').locator('text=공지사항').first();
    if (!await el.isVisible()) throw new Error('공지사항 없음');
  });

  await test('사이드 네비게이션', '"자주하는질문" 메뉴가 존재한다', async () => {
    const el = page.locator('.ant-drawer').locator('text=자주하는질문').first();
    if (!await el.isVisible()) throw new Error('자주하는질문 없음');
  });

  await test('사이드 네비게이션', '"주주총회일정" 메뉴가 존재한다', async () => {
    const el = page.locator('.ant-drawer').locator('text=주주총회일정').first();
    if (!await el.isVisible()) throw new Error('주주총회일정 없음');
  });

  // 드로어 닫기
  const mask = page.locator('.ant-drawer-mask').first();
  if (await mask.isVisible().catch(() => false)) {
    await mask.click();
    await page.waitForTimeout(500);
    console.log('  ℹ  드로어 닫음');
  }

  // ── 메인 콘텐츠 ───────────────────────────────────────────
  console.log('\n📌 메인 콘텐츠');

  await test('메인 콘텐츠', '"주주" 버튼이 존재한다', async () => {
    const el = page.locator('text=주주').first();
    if (!await el.isVisible()) throw new Error('"주주" 없음');
  });

  await test('메인 콘텐츠', '"발행회사" 버튼이 존재한다', async () => {
    const el = page.locator('text=발행회사').first();
    if (!await el.isVisible()) throw new Error('"발행회사" 없음');
  });

  await test('메인 콘텐츠', '공지사항 목록이 표시된다', async () => {
    const el = page.locator('text=공지사항').first();
    if (!await el.isVisible()) throw new Error('공지사항 없음');
  });

  // ── 푸터 ─────────────────────────────────────────────────
  console.log('\n📌 푸터');

  await test('푸터', '고객센터 전화번호 1577-6600이 표시된다', async () => {
    const el = page.locator('text=1577-6600').first();
    if (!await el.isVisible()) throw new Error('전화번호 없음');
  });

  await test('푸터', '이메일 evote@ksd.or.kr이 표시된다', async () => {
    const el = page.locator('text=evote@ksd.or.kr').first();
    if (!await el.isVisible()) throw new Error('이메일 없음');
  });

  await test('푸터', '"개인정보 처리방침" 링크가 존재한다', async () => {
    const el = page.locator('text=개인정보 처리방침').first();
    if (!await el.isVisible()) throw new Error('없음');
  });

  // ── 주주 로그인 페이지 ─────────────────────────────────
  console.log('\n📌 주주 로그인 페이지');

  await page.locator('a.circle-item.blue').first().click();
  await page.waitForURL('**/UIM_ELVT20650V', { timeout: 10000 });
  await page.waitForTimeout(800);
  console.log(`  ℹ  이동 URL: ${page.url()}`);

  await test('주주 로그인', '"주주 로그인" 제목이 표시된다', async () => {
    const el = page.locator('text=주주 로그인').first();
    if (!await el.isVisible()) throw new Error('"주주 로그인" 없음');
  });

  await test('주주 로그인', '"공동인증서" 탭이 존재한다', async () => {
    const el = page.locator('text=공동인증서').first();
    if (!await el.isVisible()) throw new Error('"공동인증서" 없음');
  });

  await test('주주 로그인', '"간편인증" 탭이 존재한다', async () => {
    const el = page.locator('text=간편인증').first();
    if (!await el.isVisible()) throw new Error('"간편인증" 없음');
  });

  await test('주주 로그인', '"카카오인증" 옵션이 존재한다', async () => {
    const el = page.locator('text=카카오인증').first();
    if (!await el.isVisible()) throw new Error('"카카오인증" 없음');
  });

  await test('주주 로그인', '"사용자등록" 링크가 존재한다', async () => {
    const el = page.locator('text=사용자등록').first();
    if (!await el.isVisible()) throw new Error('"사용자등록" 없음');
  });

  // 기관투자자 ID/PW 탭 → 일반 로그인 폼
  console.log('\n📌 기관투자자 ID/PW 로그인 폼');

  await page.locator('text=기관투자자 ID/PW').first().click();
  await page.waitForTimeout(1000);

  await test('기관투자자 로그인', 'ID/PW 탭 클릭 후 아이디 입력란이 나타난다', async () => {
    const count = await page.locator('input[type="text"], input[type="number"], input[type="tel"]').count();
    if (count === 0) throw new Error('입력란 없음');
    console.log(`           → input 수: ${count}`);
  });

  await test('기관투자자 로그인', '비밀번호 입력란이 존재한다', async () => {
    const count = await page.locator('input[type="password"]').count();
    if (count === 0) throw new Error('password input 없음');
    console.log(`           → password input 수: ${count}`);
  });

  await test('기관투자자 로그인', '"로그인" 제출 버튼이 존재한다', async () => {
    const el = page.locator('.ant-btn-primary:has-text("로그인")').first();
    if (!await el.isVisible()) throw new Error('"로그인" 버튼 없음');
  });

  // ── 반응형 ───────────────────────────────────────────────
  console.log('\n📌 반응형 (375px)');
  await page.setViewportSize({ width: 375, height: 812 });
  await page.waitForTimeout(400);

  await test('반응형', '모바일 뷰에서 페이지 본문이 렌더링된다', async () => {
    if (!await page.locator('body').first().isVisible()) throw new Error('body 미렌더링');
  });

  await test('반응형', '모바일 뷰에서 가로 스크롤이 없다', async () => {
    const sw = await page.evaluate(() => document.documentElement.scrollWidth);
    const cw = await page.evaluate(() => document.documentElement.clientWidth);
    if (sw > cw + 5) throw new Error(`가로 스크롤 발생 (${sw} > ${cw})`);
  });

  // ── 스크린샷 ──────────────────────────────────────────────
  await page.setViewportSize({ width: 1280, height: 800 });
  await page.screenshot({ path: 'evote-screenshot.png' });
  console.log('\n📸 스크린샷 저장 → evote-screenshot.png');

  // ── 결과 요약 ─────────────────────────────────────────────
  const total  = results.length;
  const passed = results.filter(r => r.status === 'pass').length;
  const failed = total - passed;

  console.log('\n' + '─'.repeat(40));
  console.log(`결과: ${total}개 중 ${passed}개 통과, ${failed}개 실패`);
  if (failed === 0) console.log('🎉 모든 테스트 통과!');
  console.log('─'.repeat(40));

  await browser.close();
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('테스트 실행 오류:', err);
  process.exit(1);
});
