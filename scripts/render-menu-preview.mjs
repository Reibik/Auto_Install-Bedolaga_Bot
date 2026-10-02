// Reproducible README illustration, generated from the actual Bash UI fixture.
// No Docker, network, real configuration or production services are accessed.
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const bash = process.env.BEDOLAGA_PREVIEW_BASH || 'bash';
const output = execFileSync(bash, ['-lc', 'bash tests/menu.sh --preview'], {
  cwd: root, encoding: 'utf8', maxBuffer: 1024 * 1024,
  env: { ...process.env, LANG: 'C.UTF-8', TZ: 'UTC' },
});
const section = output.split('--- Preview: 80 columns (fixture data) ---')[1]
  ?.split('--- Preview: 40 columns (fixture data) ---')[0];
if (!section) throw new Error('The 80-column UI fixture is missing');
const lines = section.replace(/\x1b\[[0-9;]*m/g, '').trim().split(/\r?\n/);
const escape = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;')
  .replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const height = 140 + lines.length * 29;
const rows = lines.map((line, index) => {
  const color = index === 0 ? '#8ce6ff' : line === 'Обзор' || line === 'Действия'
    ? '#c4b5fd' : line.includes('🟢') ? '#a7f3d0' : '#e2e8f0';
  return `  <text x="38" y="${98 + index * 29}" fill="${color}" xml:space="preserve">${escape(line)}</text>`;
}).join('\n');
const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1040" height="${height}" viewBox="0 0 1040 ${height}" role="img" aria-labelledby="title desc">
  <title id="title">Главное меню Bedolaga Manager</title>
  <desc id="desc">Точный вывод тестового стенда. Состояния сервисов и дата бэкапа демонстрационные.</desc>
  <rect width="1040" height="${height}" rx="20" fill="#091323"/>
  <rect x="1" y="1" width="1038" height="${height - 2}" rx="19" fill="none" stroke="#29405c"/>
  <path d="M0 56H1040" stroke="#29405c"/>
  <circle cx="30" cy="28" r="6" fill="#fb7185"/>
  <circle cx="50" cy="28" r="6" fill="#fbbf24"/>
  <circle cx="70" cy="28" r="6" fill="#34d399"/>
  <text x="520" y="34" text-anchor="middle" fill="#94a3b8" font-family="sans-serif" font-size="16">root@server:~# bedolaga</text>
  <g font-family="Consolas, DejaVu Sans Mono, monospace, Segoe UI Emoji" font-size="18">
${rows}
  </g>
  <text x="38" y="${height - 24}" fill="#94a3b8" font-family="sans-serif" font-size="14">Демонстрационный пример · данные тестового стенда</text>
</svg>
`;
const target = path.join(root, 'docs/assets/bedolaga-menu.svg');
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== svg) throw new Error('Menu preview is stale; regenerate it');
  console.log('Menu preview matches the current UI fixture.');
} else {
  writeFileSync(target, svg);
  console.log(`Generated ${target}`);
}
