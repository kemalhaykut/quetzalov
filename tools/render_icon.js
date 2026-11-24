const { chromium } = require('playwright');
const fs = require('fs'); const path = require('path');
(async () => {
  const svg = fs.readFileSync(path.join(__dirname, 'icon.svg'), 'utf8');
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  await p.setContent(`<html><body style="margin:0;background:transparent">${svg}</body></html>`);
  await p.screenshot({ path: path.join(__dirname, '..', 'assets', 'icon.png'), omitBackground: true, clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  await b.close();
})();
