const { chromium } = require('playwright');
const path = require('path');

const FILE_URL = 'file:///' + path.resolve(__dirname, 'index.html').replace(/\\/g, '/');

async function runTests() {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(FILE_URL);

  let passed = 0;
  let failed = 0;

  async function test(name, fn) {
    try {
      await fn();
      console.log(`  ✅ PASS  ${name}`);
      passed++;
    } catch (e) {
      console.log(`  ❌ FAIL  ${name}`);
      console.log(`           ${e.message}`);
      failed++;
    }
  }

  // ── Header ──────────────────────────────────────────────
  console.log('\n📌 Header');
  await test('로고 텍스트가 렌더링된다', async () => {
    const logo = await page.locator('.logo').textContent();
    if (!logo.includes('길동')) throw new Error(`로고 텍스트 없음: "${logo}"`);
  });
  await test('네비게이션 링크 4개가 존재한다', async () => {
    const count = await page.locator('nav a').count();
    if (count !== 4) throw new Error(`링크 수: ${count} (기대: 4)`);
  });

  // ── Hero ────────────────────────────────────────────────
  console.log('\n📌 Hero');
  await test('이름 "홍길동"이 표시된다', async () => {
    const name = await page.locator('.hero-name').textContent();
    if (!name.includes('홍길동')) throw new Error(`이름 없음: "${name}"`);
  });
  await test('"풀스택 개발자" 직함이 표시된다', async () => {
    const role = await page.locator('.hero-role').textContent();
    if (!role.includes('풀스택 개발자')) throw new Error(`직함 없음: "${role}"`);
  });
  await test('"프로젝트 보기" 버튼이 존재한다', async () => {
    const btn = await page.locator('.btn').textContent();
    if (!btn.includes('프로젝트 보기')) throw new Error(`버튼 텍스트 없음: "${btn}"`);
  });
  await test('CTA 버튼이 #projects로 링크된다', async () => {
    const href = await page.locator('.btn').getAttribute('href');
    if (href !== '#projects') throw new Error(`href: "${href}" (기대: #projects)`);
  });

  // ── Skills ──────────────────────────────────────────────
  console.log('\n📌 기술 스택');
  const expectedBadges = ['HTML', 'CSS', 'JavaScript', 'Python', 'Git', 'Java Backend'];
  for (const skill of expectedBadges) {
    await test(`뱃지 "${skill}"가 존재한다`, async () => {
      const badges = await page.locator('.badge').allTextContents();
      if (!badges.includes(skill)) throw new Error(`"${skill}" 뱃지 없음. 현재: ${badges.join(', ')}`);
    });
  }
  await test('뱃지가 총 6개이다', async () => {
    const count = await page.locator('.badge').count();
    if (count !== 6) throw new Error(`뱃지 수: ${count} (기대: 6)`);
  });

  // ── Projects ────────────────────────────────────────────
  console.log('\n📌 프로젝트');
  await test('프로젝트 카드가 3개 존재한다', async () => {
    const count = await page.locator('.card').count();
    if (count !== 3) throw new Error(`카드 수: ${count} (기대: 3)`);
  });
  const expectedProjects = ['할 일 관리 앱', '날씨 대시보드', '블로그 플랫폼'];
  for (const title of expectedProjects) {
    await test(`"${title}" 카드가 존재한다`, async () => {
      const titles = await page.locator('.card h3').allTextContents();
      if (!titles.includes(title)) throw new Error(`"${title}" 없음. 현재: ${titles.join(', ')}`);
    });
  }
  await test('모든 카드에 "자세히 보기" 링크가 있다', async () => {
    const links = await page.locator('.card-link').allTextContents();
    const allHaveLink = links.every(t => t.includes('자세히 보기'));
    if (!allHaveLink) throw new Error(`일부 카드에 링크 없음: ${links}`);
  });

  // ── Contact ─────────────────────────────────────────────
  console.log('\n📌 연락처');
  await test('이메일 링크가 존재한다', async () => {
    const href = await page.locator('a[href^="mailto:"]').getAttribute('href');
    if (!href) throw new Error('이메일 링크 없음');
  });
  await test('GitHub 링크가 존재한다', async () => {
    const count = await page.locator('a[href*="github"]').count();
    if (count === 0) throw new Error('GitHub 링크 없음');
  });
  await test('연락처 섹션 제목이 "연락처"이다', async () => {
    const title = await page.locator('footer .section-title').textContent();
    if (!title.includes('연락처')) throw new Error(`제목: "${title}"`);
  });

  // ── 반응형 ───────────────────────────────────────────────
  console.log('\n📌 반응형 (모바일 375px)');
  await page.setViewportSize({ width: 375, height: 812 });
  await test('모바일에서 헤더가 보인다', async () => {
    const visible = await page.locator('header').isVisible();
    if (!visible) throw new Error('헤더가 보이지 않음');
  });
  await test('모바일에서 히어로 섹션이 보인다', async () => {
    const visible = await page.locator('#hero').isVisible();
    if (!visible) throw new Error('히어로 섹션이 보이지 않음');
  });

  // ── 결과 요약 ────────────────────────────────────────────
  console.log('\n' + '─'.repeat(40));
  console.log(`결과: ${passed + failed}개 중 ${passed}개 통과, ${failed}개 실패`);
  if (failed === 0) {
    console.log('🎉 모든 테스트 통과!');
  }
  console.log('─'.repeat(40));

  await browser.close();
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('테스트 실행 오류:', err);
  process.exit(1);
});
