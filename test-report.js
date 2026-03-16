const { chromium } = require('playwright');
const path = require('path');
const fs = require('fs');

const FILE_URL = 'file:///' + path.resolve(__dirname, 'index.html').replace(/\\/g, '/');

async function runTests() {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto(FILE_URL);

  const results = [];

  async function test(section, name, fn) {
    try {
      await fn();
      results.push({ section, name, status: 'pass' });
    } catch (e) {
      results.push({ section, name, status: 'fail', error: e.message });
    }
  }

  // Header
  await test('Header', '로고 텍스트가 렌더링된다', async () => {
    const logo = await page.locator('.logo').textContent();
    if (!logo.includes('길동')) throw new Error(`로고 텍스트 없음: "${logo}"`);
  });
  await test('Header', '네비게이션 링크 4개가 존재한다', async () => {
    const count = await page.locator('nav a').count();
    if (count !== 4) throw new Error(`링크 수: ${count} (기대: 4)`);
  });

  // Hero
  await test('Hero', '이름 "홍길동"이 표시된다', async () => {
    const name = await page.locator('.hero-name').textContent();
    if (!name.includes('홍길동')) throw new Error(`이름 없음: "${name}"`);
  });
  await test('Hero', '"풀스택 개발자" 직함이 표시된다', async () => {
    const role = await page.locator('.hero-role').textContent();
    if (!role.includes('풀스택 개발자')) throw new Error(`직함 없음: "${role}"`);
  });
  await test('Hero', '"프로젝트 보기" 버튼이 존재한다', async () => {
    const btn = await page.locator('.btn').textContent();
    if (!btn.includes('프로젝트 보기')) throw new Error(`버튼 텍스트 없음: "${btn}"`);
  });
  await test('Hero', 'CTA 버튼이 #projects로 링크된다', async () => {
    const href = await page.locator('.btn').getAttribute('href');
    if (href !== '#projects') throw new Error(`href: "${href}" (기대: #projects)`);
  });

  // Skills
  const expectedBadges = ['HTML', 'CSS', 'JavaScript', 'Python', 'Git', 'Java Backend'];
  for (const skill of expectedBadges) {
    await test('기술 스택', `뱃지 "${skill}"가 존재한다`, async () => {
      const badges = await page.locator('.badge').allTextContents();
      if (!badges.includes(skill)) throw new Error(`"${skill}" 뱃지 없음`);
    });
  }
  await test('기술 스택', '뱃지가 총 6개이다', async () => {
    const count = await page.locator('.badge').count();
    if (count !== 6) throw new Error(`뱃지 수: ${count} (기대: 6)`);
  });

  // Projects
  await test('프로젝트', '프로젝트 카드가 3개 존재한다', async () => {
    const count = await page.locator('.card').count();
    if (count !== 3) throw new Error(`카드 수: ${count} (기대: 3)`);
  });
  for (const title of ['할 일 관리 앱', '날씨 대시보드', '블로그 플랫폼']) {
    await test('프로젝트', `"${title}" 카드가 존재한다`, async () => {
      const titles = await page.locator('.card h3').allTextContents();
      if (!titles.includes(title)) throw new Error(`"${title}" 없음`);
    });
  }
  await test('프로젝트', '모든 카드에 "자세히 보기" 링크가 있다', async () => {
    const links = await page.locator('.card-link').allTextContents();
    if (!links.every(t => t.includes('자세히 보기'))) throw new Error('일부 카드에 링크 없음');
  });

  // Contact
  await test('연락처', '이메일 링크가 존재한다', async () => {
    const href = await page.locator('a[href^="mailto:"]').getAttribute('href');
    if (!href) throw new Error('이메일 링크 없음');
  });
  await test('연락처', 'GitHub 링크가 존재한다', async () => {
    const count = await page.locator('a[href*="github"]').count();
    if (count === 0) throw new Error('GitHub 링크 없음');
  });
  await test('연락처', '연락처 섹션 제목이 "연락처"이다', async () => {
    const title = await page.locator('footer .section-title').textContent();
    if (!title.includes('연락처')) throw new Error(`제목: "${title}"`);
  });

  // Responsive
  await page.setViewportSize({ width: 375, height: 812 });
  await test('반응형 (375px)', '모바일에서 헤더가 보인다', async () => {
    if (!await page.locator('header').isVisible()) throw new Error('헤더가 보이지 않음');
  });
  await test('반응형 (375px)', '모바일에서 히어로 섹션이 보인다', async () => {
    if (!await page.locator('#hero').isVisible()) throw new Error('히어로 섹션이 보이지 않음');
  });

  await browser.close();

  // ── Build HTML report ──
  const total = results.length;
  const passed = results.filter(r => r.status === 'pass').length;
  const failed = total - passed;
  const sections = [...new Set(results.map(r => r.section))];
  const now = new Date().toLocaleString('ko-KR');

  const sectionRows = sections.map(sec => {
    const items = results.filter(r => r.section === sec);
    const rows = items.map(r => `
      <tr class="${r.status}">
        <td class="icon">${r.status === 'pass' ? '✅' : '❌'}</td>
        <td>${r.name}</td>
        <td class="status-cell ${r.status}">${r.status.toUpperCase()}</td>
        ${r.error ? `<td class="error">${r.error}</td>` : '<td>—</td>'}
      </tr>`).join('');
    return `
      <tr class="section-header">
        <td colspan="4">📌 ${sec}</td>
      </tr>
      ${rows}`;
  }).join('');

  const html = `<!DOCTYPE html>
<html lang="ko">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Test Report</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Segoe UI', sans-serif; background: #0f0f1a; color: #eee; padding: 2rem; }
    h1 { font-size: 1.6rem; margin-bottom: 0.3rem; }
    .meta { color: #888; font-size: 0.85rem; margin-bottom: 2rem; }

    .summary { display: flex; gap: 1rem; margin-bottom: 2rem; flex-wrap: wrap; }
    .stat { background: #1a1a2e; border-radius: 8px; padding: 1rem 2rem; text-align: center; flex: 1; min-width: 120px; }
    .stat .num { font-size: 2.2rem; font-weight: 700; }
    .stat .label { font-size: 0.8rem; color: #888; margin-top: 0.2rem; }
    .stat.total .num  { color: #aaa; }
    .stat.green .num  { color: #4caf50; }
    .stat.red   .num  { color: #e94560; }

    .progress { height: 6px; background: #1a1a2e; border-radius: 3px; margin-bottom: 2rem; overflow: hidden; }
    .progress-bar { height: 100%; background: ${failed === 0 ? '#4caf50' : '#e94560'}; width: ${Math.round((passed/total)*100)}%; border-radius: 3px; }

    table { width: 100%; border-collapse: collapse; background: #1a1a2e; border-radius: 8px; overflow: hidden; }
    th { background: #16213e; padding: 0.75rem 1rem; text-align: left; font-size: 0.8rem; color: #888; text-transform: uppercase; letter-spacing: 0.05em; }
    td { padding: 0.65rem 1rem; border-bottom: 1px solid #0f0f1a; font-size: 0.9rem; }
    td.icon { width: 36px; text-align: center; }
    td.error { color: #e94560; font-size: 0.8rem; }

    tr.section-header td { background: #16213e; color: #e94560; font-weight: 700; font-size: 0.9rem; padding: 0.6rem 1rem; }
    tr.pass:hover  { background: rgba(76,175,80,0.05); }
    tr.fail:hover  { background: rgba(233,69,96,0.08); }

    .status-cell { font-size: 0.75rem; font-weight: 700; letter-spacing: 0.05em; }
    .status-cell.pass { color: #4caf50; }
    .status-cell.fail { color: #e94560; }

    .footer { margin-top: 1.5rem; text-align: center; color: #555; font-size: 0.8rem; }
  </style>
</head>
<body>
  <h1>🧪 Playwright Test Report</h1>
  <p class="meta">홍길동 포트폴리오 · 실행 시각: ${now}</p>

  <div class="summary">
    <div class="stat total"><div class="num">${total}</div><div class="label">TOTAL</div></div>
    <div class="stat green"><div class="num">${passed}</div><div class="label">PASSED</div></div>
    <div class="stat red"><div class="num">${failed}</div><div class="label">FAILED</div></div>
    <div class="stat ${failed===0?'green':'red'}"><div class="num">${Math.round((passed/total)*100)}%</div><div class="label">PASS RATE</div></div>
  </div>

  <div class="progress"><div class="progress-bar"></div></div>

  <table>
    <thead>
      <tr>
        <th></th>
        <th>테스트 이름</th>
        <th>결과</th>
        <th>오류 메시지</th>
      </tr>
    </thead>
    <tbody>
      ${sectionRows}
    </tbody>
  </table>

  <p class="footer">${failed === 0 ? '🎉 모든 테스트 통과!' : `${failed}개 테스트 실패`}</p>
</body>
</html>`;

  fs.writeFileSync('report.html', html, 'utf-8');
  console.log(`리포트 생성 완료 → report.html  (${passed}/${total} 통과)`);
  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(err => {
  console.error('오류:', err);
  process.exit(1);
});
