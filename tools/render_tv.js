// Android uyarlanabilir ikon ön planı (arka plansız) + Android TV banner'ı üretir.
const { chromium } = require('playwright');
const fs = require('fs'); const path = require('path');
(async () => {
  const svg = fs.readFileSync(path.join(__dirname, 'icon.svg'), 'utf8');
  // arka plan dikdörtgenini kaldır, kuşu güvenli alana (orta %62) küçült
  const inner = svg.replace(/<svg[^>]*>/, '').replace('</svg>', '').replace(/<rect width="1024" height="1024"[^>]*\/>/, '');
  const fg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024"><g transform="translate(512 512) scale(0.62) translate(-512 -490)">${inner}</g></svg>`;
  const b = await chromium.launch();
  let p;
  if (process.argv.includes('--fg')) {
  p = await b.newPage({ viewport: { width: 1024, height: 1024 } });
  await p.setContent(`<html><body style="margin:0;background:transparent">${fg}</body></html>`);
  await p.screenshot({ path: path.join(__dirname, '..', 'assets', 'icon_fg.png'), omitBackground: true });
  }
  const iconB64 = fs.readFileSync(path.join(__dirname, '..', 'assets', 'icon.png')).toString('base64');
  const font = path.join(__dirname, '..', 'assets', 'fonts', 'Poppins-ExtraBold.ttf');
  const fontCss = fs.existsSync(font) ? `@font-face{font-family:P;src:url(data:font/ttf;base64,${fs.readFileSync(font).toString('base64')})}` : '';
  p = await b.newPage({ viewport: { width: 320, height: 180 }, deviceScaleFactor: 2 });
  await p.setContent(`<html><head><style>${fontCss}
    body{margin:0;width:320px;height:180px;background:radial-gradient(circle at 25% 40%,#3a2408,#060504 70%);display:flex;align-items:center;gap:14px;padding:0 22px;box-sizing:border-box;font-family:P,Poppins,sans-serif}
    img{width:92px;height:92px;border-radius:20px;box-shadow:0 0 24px rgba(255,106,26,.45)}
    .t{font-size:34px;font-weight:800;background:linear-gradient(90deg,#f8dc8c,#c98d2c);-webkit-background-clip:text;color:transparent;line-height:1}
    .s{color:#bbb;font-size:13px;letter-spacing:3px;margin-top:6px}
  </style></head><body><img src="data:image/png;base64,${iconB64}"><div><div class="t">Quetzalov</div><div class="s">IPTV · TV</div></div></body></html>`);
  await p.screenshot({ path: path.join(__dirname, '..', 'assets', 'tv_banner.png') });
  await b.close();
})();
