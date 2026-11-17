// 生成“趴在白色卡片上探头”的吉祥物图标（参考 OmoFun 的构图，不复制其角色/文字/素材）。
// 原创角色：长直深色头发、蓝眼、姬发式、冷静里带一点害羞；星形发针是原创记号。
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const OUT = dirname(fileURLToPath(import.meta.url));
mkdirSync(OUT, { recursive: true });

const variants = [
  {
    id: 'p01', name: 'P01 蓝调·四点', tag: '蓝底 · 四点标识 · 最像参考图的构图',
    bg: ['#A9C8F5', '#E6F1FF'], halo: '#FFFFFF', haloOpacity: 0.20,
    mark: 'dots',
    hair: '#232840', hairSide: '#2E3456', hairHi: '#5B6A9E', hairShadow: '#15182A',
    skin: '#FFE9DF', skinShade: '#F2C7B7', lash: '#1B1E30',
    eyeA: '#3E7FAF', eyeB: '#B4E3F8', irisDark: '#163247',
    pinColor: '#FFD36E', pinDark: '#8A5B00',
    mouth: 'open', brow: 'serious', blush: 0.38,
    desc: '最贴参考图的“趴在白卡上探头”：蓝底、白卡、双手扒边，顶部四点代替字标。'
  },
  {
    id: 'p02', name: 'P02 蓝调·字标', tag: '蓝底 · “聚合”字标 · 更像成品 App',
    bg: ['#6F9FE4', '#D3E6FF'], halo: '#FFFFFF', haloOpacity: 0.22,
    mark: 'wordmark',
    hair: '#232840', hairSide: '#2E3456', hairHi: '#5B6A9E', hairShadow: '#15182A',
    skin: '#FFE9DF', skinShade: '#F2C7B7', lash: '#1B1E30',
    eyeA: '#3E7FAF', eyeB: '#B4E3F8', irisDark: '#163247',
    pinColor: '#FFD36E', pinDark: '#8A5B00',
    mouth: 'open', brow: 'serious', blush: 0.34,
    desc: '把顶部换成“聚合”字标（占位名，可换最终 App 名），更接近参考图那种成品图标。'
  },
  {
    id: 'p03', name: 'P03 樱调', tag: '玫瑰底 · 小微笑 · 更软',
    bg: ['#F6B8CB', '#FFE7EF'], halo: '#FFFFFF', haloOpacity: 0.24,
    mark: 'star',
    hair: '#2A2330', hairSide: '#382F40', hairHi: '#655A78', hairShadow: '#19141E',
    skin: '#FFE9DF', skinShade: '#F4C6B8', lash: '#211A24',
    eyeA: '#4A82B2', eyeB: '#C4E8F7', irisDark: '#1B3145',
    pinColor: '#FFF0B8', pinDark: '#9A6A2C',
    mouth: 'smile', brow: 'soft', blush: 0.58,
    desc: '同一构图换成玫瑰底、小微笑和明显腮红；更可爱，澪的“冷静”会淡一点。'
  },
  {
    id: 'p04', name: 'P04 夜调', tag: '深色底 · 白卡 · 小尺寸最稳',
    bg: ['#3B3555', '#1B192A'], halo: '#EADDFF', haloOpacity: 0.14,
    mark: 'sparkle',
    hair: '#262B45', hairSide: '#303758', hairHi: '#66709B', hairShadow: '#141726',
    skin: '#FFE6DA', skinShade: '#EDBFAE', lash: '#191B2B',
    eyeA: '#4C8FC4', eyeB: '#C6ECFB', irisDark: '#142C3E',
    pinColor: '#CFC3F5', pinDark: '#3A2E57',
    mouth: 'calm', brow: 'serious', blush: 0.2,
    desc: '深色底 + 白卡，高对比；在深色任务栏或深色主题下最稳，16px 也清楚。'
  }
];

function eye(v, cx, side) {
  const ox = side === 'L' ? cx - 23 : cx + 23;
  const dx = side === 'L' ? -8 : 8;
  return `<g>
    <ellipse cx="${cx}" cy="270" rx="23" ry="27" fill="#FFFDF8"/>
    <path d="M ${cx - 22} 264 C ${cx - 16} 243 ${cx + 16} 243 ${cx + 22} 264"
          fill="none" stroke="${v.lash}" stroke-width="5.5" stroke-linecap="round"/>
    <ellipse cx="${cx}" cy="272" rx="16" ry="21" fill="url(#iris-${v.id})"/>
    <ellipse cx="${cx}" cy="274" rx="7.5" ry="13" fill="${v.irisDark}"/>
    <circle cx="${cx - 5}" cy="266" r="5.5" fill="#FFFFFF" opacity="0.96"/>
    <circle cx="${cx + 6}" cy="280" r="2.8" fill="#FFFFFF" opacity="0.72"/>
    <path d="M ${ox} 264 L ${ox + dx} 254 L ${ox + dx * 0.4} 274 Z" fill="${v.lash}"/>
  </g>`;
}

function hand(v, x, mirror) {
  const m = mirror ? ' scale(-1 1)' : '';
  return `<g transform="translate(${x} 348)${m}">
    <ellipse cx="24" cy="38" rx="29" ry="8" fill="#000000" opacity="0.06"/>
    <rect x="4" y="-20" width="10" height="25" rx="5" fill="${v.skin}" stroke="${v.skinShade}" stroke-width="2.4"/>
    <rect x="18" y="-23" width="10" height="28" rx="5" fill="${v.skin}" stroke="${v.skinShade}" stroke-width="2.4"/>
    <rect x="32" y="-20" width="10" height="25" rx="5" fill="${v.skin}" stroke="${v.skinShade}" stroke-width="2.4"/>
    <rect x="0" y="0" width="46" height="34" rx="16" fill="${v.skin}" stroke="${v.skinShade}" stroke-width="3"/>
    <path d="M9 12 C 16 20 30 20 37 12" fill="none" stroke="${v.skinShade}" stroke-width="2.4" opacity="0.65" stroke-linecap="round"/>
  </g>`;
}

function mark(v) {
  if (v.mark === 'dots') {
    const cols = ['#6750A4', '#B3476A', '#00696D', '#8B5000'];
    return `<g>${cols.map((c, i) => `<circle cx="${176 + i * 40}" cy="84" r="9" fill="${c}" stroke="#FFFFFF" stroke-width="3"/>`).join('')}</g>`;
  }
  if (v.mark === 'wordmark') {
    return `<g text-anchor="middle" font-family="'Microsoft YaHei UI','Noto Sans SC','Source Han Sans SC',sans-serif">
      <text x="256" y="89" font-size="54" font-weight="800" fill="#3E5E8E" opacity="0.45" letter-spacing="4">聚合</text>
      <text x="256" y="86" font-size="54" font-weight="800" fill="#FFFFFF" letter-spacing="4">聚合</text>
    </g>`;
  }
  if (v.mark === 'star') {
    return `<g transform="translate(362 88)">
      <path d="M0 -18 L5 -5 L18 0 L5 5 L0 18 L-5 5 L-18 0 L-5 -5 Z" fill="#FFFFFF" opacity="0.92"/>
    </g>`;
  }
  return `<g>
    <g transform="translate(364 84)">
      <path d="M0 -15 L4 -4 L15 0 L4 4 L0 15 L-4 4 L-15 0 L-4 -4 Z" fill="#FFFFFF" opacity="0.95"/>
    </g>
    <g transform="translate(150 112) scale(0.55)">
      <path d="M0 -15 L4 -4 L15 0 L4 4 L0 15 L-4 4 L-15 0 L-4 -4 Z" fill="#EADDFF" opacity="0.8"/>
    </g>
  </g>`;
}

function character(v) {
  return `
  <!-- 后发 -->
  <path d="M256 108 C 156 108 108 178 108 272 C 108 330 116 382 128 430 L 384 430 C 396 382 404 330 404 272 C 404 178 356 108 256 108 Z"
        fill="${v.hair}" stroke="${v.hairHi}" stroke-opacity="0.22" stroke-width="4"/>
  <!-- 呆毛（原创吉祥物记号） -->
  <path d="M256 112 C 244 90 252 72 268 70 C 282 68 290 80 282 90 C 276 98 266 96 266 88"
        fill="none" stroke="${v.hair}" stroke-width="9" stroke-linecap="round"/>
  <!-- 脸 -->
  <ellipse cx="256" cy="258" rx="92" ry="98" fill="${v.skin}"/>
  <path d="M176 300 C 184 340 214 358 256 358 C 298 358 328 340 336 300 C 318 340 290 348 256 348 C 222 348 194 340 176 300 Z"
        fill="${v.skinShade}" opacity="0.32"/>
  <!-- 刘海 -->
  <path d="M156 224 C 158 158 204 118 256 118 C 308 118 354 158 356 224 C 326 214 292 220 256 218 C 220 220 186 214 156 224 Z" fill="${v.hair}"/>
  <path d="M176 200 C 190 150 222 124 270 120" fill="none" stroke="${v.hairHi}" stroke-width="9" opacity="0.42" stroke-linecap="round"/>
  <path d="M164 224 C 200 216 312 216 348 224 L 348 244 C 312 236 200 236 164 244 Z" fill="#000000" opacity="0.07"/>
  <!-- 眉毛 -->
  ${v.brow === 'soft'
    ? `<path d="M184 238 Q 208 229 230 236" fill="none" stroke="${v.hair}" stroke-width="4.6" opacity="0.8" stroke-linecap="round"/>
       <path d="M282 236 Q 304 229 328 238" fill="none" stroke="${v.hair}" stroke-width="4.6" opacity="0.8" stroke-linecap="round"/>`
    : `<path d="M184 234 Q 210 240 230 238" fill="none" stroke="${v.hair}" stroke-width="4.6" opacity="0.8" stroke-linecap="round"/>
       <path d="M282 238 Q 302 240 328 234" fill="none" stroke="${v.hair}" stroke-width="4.6" opacity="0.8" stroke-linecap="round"/>`}
  <!-- 眼睛 -->
  ${eye(v, 216, 'L')}
  ${eye(v, 296, 'R')}
  <!-- 鼻子 / 嘴 -->
  <path d="M254 296 Q 257 299 260 296" fill="none" stroke="${v.skinShade}" stroke-width="3.6" stroke-linecap="round"/>
  ${v.mouth === 'smile'
    ? `<path d="M246 310 Q 256 321 266 310" fill="none" stroke="#B96363" stroke-width="4" stroke-linecap="round"/>`
    : v.mouth === 'open'
      ? `<ellipse cx="256" cy="312" rx="5.5" ry="4.4" fill="#B96363"/><path d="M251 310 Q 256 307 261 310" fill="none" stroke="#B96363" stroke-width="2.6" stroke-linecap="round"/>`
      : `<path d="M248 312 Q 256 313 264 312" fill="none" stroke="#B96363" stroke-width="3.8" stroke-linecap="round"/>`}
  <!-- 腮红 -->
  <ellipse cx="184" cy="302" rx="22" ry="10" fill="#F29BAA" opacity="${v.blush}"/>
  <ellipse cx="328" cy="302" rx="22" ry="10" fill="#F29BAA" opacity="${v.blush}"/>
  <!-- 星形发针 -->
  <g transform="translate(350 196)" stroke-linejoin="round">
    <path d="M0 -22 L6.5 -6.5 L22 0 L6.5 6.5 L0 22 L-6.5 6.5 L-22 0 L-6.5 -6.5 Z"
          fill="${v.pinColor}" stroke="${v.pinDark}" stroke-width="3"/>
    <circle r="3.4" fill="#FFF9E4"/>
  </g>`;
}

function card(v) {
  return `
  <!-- 白卡阴影 -->
  <rect x="52" y="360" width="408" height="136" rx="36" fill="#000000" opacity="0.10"/>
  <!-- 白卡 -->
  <rect x="46" y="350" width="420" height="136" rx="36" fill="#FFFDFB"/>
  <rect x="62" y="358" width="388" height="5" rx="2.5" fill="#FFFFFF" opacity="0.75"/>
  <!-- 长侧发（搭在白卡上） -->
  <path d="M154 224 C 134 284 132 360 142 434 C 146 460 166 468 180 450 C 164 384 164 300 172 230 Z" fill="${v.hairSide}"/>
  <path d="M358 224 C 378 284 380 360 370 434 C 366 460 346 468 332 450 C 348 384 348 300 340 230 Z" fill="${v.hairSide}"/>
  <path d="M165 232 C 156 300 158 380 172 440" fill="none" stroke="${v.hairHi}" stroke-width="5.5" opacity="0.34" stroke-linecap="round"/>
  <path d="M347 232 C 356 300 354 380 340 440" fill="none" stroke="${v.hairHi}" stroke-width="5.5" opacity="0.34" stroke-linecap="round"/>
  ${hand(v, 142, false)}
  ${hand(v, 368, true)}`;
}

function appSvg(v) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="${v.name}">
  <defs>
    <linearGradient id="bg-${v.id}" x1="0" y1="0" x2="0.4" y2="1">
      <stop offset="0" stop-color="${v.bg[0]}"/>
      <stop offset="1" stop-color="${v.bg[1]}"/>
    </linearGradient>
    <linearGradient id="iris-${v.id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${v.eyeB}"/>
      <stop offset="1" stop-color="${v.eyeA}"/>
    </linearGradient>
    <clipPath id="clip-${v.id}"><rect width="512" height="512" rx="116"/></clipPath>
  </defs>
  <g clip-path="url(#clip-${v.id})">
    <rect width="512" height="512" fill="url(#bg-${v.id})"/>
    <circle cx="256" cy="238" r="178" fill="${v.halo}" opacity="${v.haloOpacity}"/>
    <circle cx="92" cy="86" r="54" fill="#FFFFFF" opacity="0.10"/>
    <circle cx="424" cy="420" r="76" fill="#000000" opacity="0.04"/>
    ${mark(v)}
    ${character(v)}
    ${card(v)}
  </g>
</svg>
`;
}

function bareSvg(v) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="${v.name} 透明底">
  <defs>
    <linearGradient id="iris-${v.id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${v.eyeB}"/>
      <stop offset="1" stop-color="${v.eyeA}"/>
    </linearGradient>
  </defs>
  ${character(v)}
  ${card(v)}
</svg>
`;
}

for (const v of variants) {
  writeFileSync(join(OUT, `peek_${v.id}.svg`), appSvg(v), 'utf8');
  writeFileSync(join(OUT, `bare_${v.id}.svg`), bareSvg(v), 'utf8');
}

writeFileSync(
  join(OUT, 'peek-variants.json'),
  JSON.stringify(variants.map(({ id, name, tag, desc }) => ({ id, name, tag, desc })), null, 2),
  'utf8'
);

console.log(`generated ${variants.length * 2} peek svg files in ${OUT}`);
