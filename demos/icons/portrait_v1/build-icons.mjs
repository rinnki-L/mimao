// 生成四版原创角色图标（应用图标 + 透明头部版）。
// 只借“长直深色头发 / 蓝眼 / 姬发式 / 冷静里带一点害羞”的气质；
// 不使用任何 K-On! 官方线条、制服、校徽或 HTT 标志。
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const OUT = dirname(fileURLToPath(import.meta.url));
mkdirSync(OUT, { recursive: true });

const variants = [
  {
    id: 'm01', name: '星屑', tag: '冷静 · 星形发针 · 薰衣草底',
    bg: ['#EEE3FF', '#C7AEF5'], halo: '#FFFFFF', haloOpacity: 0.18,
    hair: '#232840', hairHi: '#525C86', hairSide: '#2E3456', hairShadow: '#15182A',
    skin: '#FFE9DE', skinShade: '#F2C7B7', lash: '#1B1E30',
    eyeA: '#3E7FAF', eyeB: '#A9DDF5', irisDark: '#163247',
    cloth: '#2B3048', clothHi: '#5A638C',
    pin: 'star', pinColor: '#FFD36E', pinDark: '#8A5B00',
    mouth: 'calm', brow: 'serious', blush: 0.3, gaze: [0, 0],
    desc: '最接近“像澪”的气质：长直蓝黑发、姬发式、蓝眼、表情克制。星形发针是原创记号。'
  },
  {
    id: 'm02', name: '夜曲', tag: '深色底 · 音符发针 · 任务栏友好',
    bg: ['#4B3B5B', '#241B2F'], halo: '#EADDFF', haloOpacity: 0.16,
    hair: '#262B45', hairHi: '#66709B', hairSide: '#303758', hairShadow: '#141726',
    skin: '#FFE6DA', skinShade: '#EDBFAE', lash: '#191B2B',
    eyeA: '#4C8FC4', eyeB: '#BCE7FA', irisDark: '#142C3E',
    cloth: '#1C2134', clothHi: '#4D577F',
    pin: 'note', pinColor: '#CFC3F5', pinDark: '#3A2E57',
    mouth: 'calm', brow: 'serious', blush: 0.18, gaze: [2, 0],
    desc: '同一角色，深色底 + 音符发针，侧目一点点。放在深色任务栏或浅色桌面都不糊。'
  },
  {
    id: 'm03', name: '微光', tag: '微笑 · 腮红 · 玫瑰底',
    bg: ['#FFE4EC', '#F6B8CB'], halo: '#FFFFFF', haloOpacity: 0.22,
    hair: '#2A2330', hairHi: '#655A78', hairSide: '#382F40', hairShadow: '#19141E',
    skin: '#FFE9DF', skinShade: '#F4C6B8', lash: '#211A24',
    eyeA: '#4A82B2', eyeB: '#B7E0F2', irisDark: '#1B3145',
    cloth: '#372A36', clothHi: '#6B5363',
    pin: 'star', pinColor: '#FFF0B8', pinDark: '#9A6A2C',
    mouth: 'smile', brow: 'soft', blush: 0.55, gaze: [0, 1],
    desc: '更软、更可爱：小微笑、腮红明显。代价是澪那种“冷静/别扭”会淡一点。'
  },
  {
    id: 'm04', name: '墨', tag: '近单色 · 高对比 · 小尺寸最稳',
    bg: ['#F6F2E9', '#D8D0C0'], halo: '#FFFFFF', haloOpacity: 0.24,
    hair: '#1F1F28', hairHi: '#5A5A68', hairSide: '#2A2A34', hairShadow: '#101016',
    skin: '#FBF3E8', skinShade: '#E6D5C2', lash: '#17171D',
    eyeA: '#3C6E92', eyeB: '#9CC7DD', irisDark: '#152A38',
    cloth: '#23232B', clothHi: '#5A5A66',
    pin: 'none', pinColor: '#000000', pinDark: '#000000',
    mouth: 'calm', brow: 'serious', blush: 0.12, gaze: [0, 0],
    desc: '去掉发针、压低色彩，只留深发/浅脸/蓝眼。16px 下最清楚，但个性最弱。'
  }
];

function eye(v, cx, side) {
  const [gx, gy] = v.gaze;
  const ox = side === 'L' ? cx - 25 : cx + 25;
  const dx = side === 'L' ? -8 : 8;
  return `
    <g>
      <ellipse cx="${cx}" cy="316" rx="25" ry="30" fill="#FFFDF8"/>
      <path d="M ${cx - 24} 310 C ${cx - 18} 285 ${cx + 18} 285 ${cx + 24} 310"
            fill="none" stroke="${v.lash}" stroke-width="6" stroke-linecap="round"/>
      <ellipse cx="${cx + gx}" cy="${318 + gy}" rx="17" ry="23" fill="url(#iris-${v.id})"/>
      <ellipse cx="${cx + gx}" cy="${320 + gy}" rx="8" ry="14" fill="${v.irisDark}"/>
      <circle cx="${cx + gx - 6}" cy="${312 + gy}" r="6" fill="#FFFFFF" opacity="0.95"/>
      <circle cx="${cx + gx + 6}" cy="${326 + gy}" r="3" fill="#FFFFFF" opacity="0.72"/>
      <path d="M ${ox} 310 L ${ox + dx} 299 L ${ox + dx * 0.4} 320 Z" fill="${v.lash}"/>
    </g>`;
}

function pin(v) {
  if (v.pin === 'none') return '';
  if (v.pin === 'star') {
    return `
    <g transform="translate(350 198)" stroke-linejoin="round">
      <path d="M0 -27 L8 -8 L27 0 L8 8 L0 27 L-8 8 L-27 0 L-8 -8 Z"
            fill="${v.pinColor}" stroke="${v.pinDark}" stroke-width="3.5"/>
      <circle r="4.2" fill="#FFF9E4"/>
    </g>`;
  }
  return `
    <g transform="translate(350 196) rotate(-8)" stroke-linejoin="round">
      <ellipse cx="-9" cy="21" rx="10" ry="7.5" fill="${v.pinColor}" stroke="${v.pinDark}" stroke-width="3"/>
      <rect x="-2" y="-15" width="5" height="37" rx="2.5" fill="${v.pinColor}" stroke="${v.pinDark}" stroke-width="2"/>
      <path d="M3 -15 C 14 -11 19 0 15 9 C 10 1 6 -3 3 -5 Z" fill="${v.pinColor}" stroke="${v.pinDark}" stroke-width="2"/>
    </g>`;
}

function mouth(v) {
  if (v.mouth === 'smile') {
    return `<path d="M240 372 Q256 388 272 372" fill="none" stroke="#B96363" stroke-width="4.5" stroke-linecap="round"/>`;
  }
  return `<path d="M246 377 Q256 378 266 377" fill="none" stroke="#B96363" stroke-width="4.2" stroke-linecap="round"/>`;
}

function head(v) {
  return `
  <g>
    <!-- 后发 -->
    <path d="M256 64 C 144 64 88 148 88 264 C 88 356 104 448 128 512 L 384 512 C 408 448 424 356 424 264 C 424 148 368 64 256 64 Z"
          fill="${v.hair}" stroke="${v.hairHi}" stroke-opacity="0.22" stroke-width="4"/>
    <!-- 脖子 -->
    <path d="M228 392 C 228 432 220 454 208 472 L 304 472 C 292 454 284 432 284 392 Z" fill="${v.skinShade}"/>
    <!-- 衣服领口 -->
    <path d="M166 512 C 172 476 198 456 222 446 L 256 470 L 290 446 C 314 456 340 476 346 512 Z" fill="${v.cloth}"/>
    <path d="M222 446 L256 470 L290 446" fill="none" stroke="${v.clothHi}" stroke-width="4" opacity="0.55"/>
    <!-- 脸 -->
    <ellipse cx="256" cy="288" rx="110" ry="120" fill="${v.skin}"/>
    <path d="M158 336 C 168 386 206 410 256 410 C 306 410 344 386 354 336 C 332 388 296 400 256 400 C 216 400 180 388 158 336 Z"
          fill="${v.skinShade}" opacity="0.35"/>
    <!-- 侧发（姬发式）：比后发略浅，让“两束前发”读得出来 -->
    <path d="M146 238 C 128 292 126 352 138 404 C 142 420 160 428 174 418 C 160 366 158 300 166 242 Z" fill="${v.hairSide}"/>
    <path d="M366 238 C 384 292 386 352 374 404 C 370 420 352 428 338 418 C 352 366 354 300 346 242 Z" fill="${v.hairSide}"/>
    <path d="M165 244 C 158 300 160 366 172 414" fill="none" stroke="${v.hairShadow}" stroke-width="3" opacity="0.35" stroke-linecap="round"/>
    <path d="M347 244 C 354 300 352 366 340 414" fill="none" stroke="${v.hairShadow}" stroke-width="3" opacity="0.35" stroke-linecap="round"/>
    <path d="M157 272 C 147 320 147 366 155 400" fill="none" stroke="${v.hairHi}" stroke-width="6" opacity="0.34" stroke-linecap="round"/>
    <path d="M355 272 C 365 320 365 366 357 400" fill="none" stroke="${v.hairHi}" stroke-width="6" opacity="0.34" stroke-linecap="round"/>
    <!-- 刘海 -->
    <path d="M148 252 C 150 176 198 132 256 132 C 314 132 362 176 364 252 C 330 242 292 248 256 246 C 220 248 182 242 148 252 Z" fill="${v.hair}"/>
    <path d="M170 222 C 184 160 222 126 274 120" fill="none" stroke="${v.hairHi}" stroke-width="10" opacity="0.42" stroke-linecap="round"/>
    <path d="M196 244 C 202 200 220 170 246 150" fill="none" stroke="${v.hairHi}" stroke-width="6" opacity="0.24" stroke-linecap="round"/>
    <!-- 刘海在额头上的投影 -->
    <path d="M160 252 C 198 244 314 244 352 252 L 352 274 C 314 264 198 264 160 274 Z" fill="#000000" opacity="0.07"/>
    <!-- 眉毛：serious = 内端略低，冷静一点；soft = 平缓 -->
    ${v.brow === 'soft'
      ? `<path d="M180 272 Q 206 262 232 270" fill="none" stroke="${v.hair}" stroke-width="5" opacity="0.8" stroke-linecap="round"/>
         <path d="M280 270 Q 306 262 332 272" fill="none" stroke="${v.hair}" stroke-width="5" opacity="0.8" stroke-linecap="round"/>`
      : `<path d="M180 268 Q 208 274 232 272" fill="none" stroke="${v.hair}" stroke-width="5" opacity="0.8" stroke-linecap="round"/>
         <path d="M280 272 Q 304 274 332 268" fill="none" stroke="${v.hair}" stroke-width="5" opacity="0.8" stroke-linecap="round"/>`}
    <!-- 眼睛 -->
    ${eye(v, 206, 'L')}
    ${eye(v, 306, 'R')}
    <!-- 鼻子 / 嘴 -->
    <path d="M254 352 Q 257 355 260 352" fill="none" stroke="${v.skinShade}" stroke-width="4" stroke-linecap="round"/>
    ${mouth(v)}
    <!-- 腮红 -->
    <ellipse cx="178" cy="360" rx="24" ry="11" fill="#F29BAA" opacity="${v.blush}"/>
    <ellipse cx="334" cy="360" rx="24" ry="11" fill="#F29BAA" opacity="${v.blush}"/>
    <!-- 发针 -->
    ${pin(v)}
  </g>`;
}

function appSvg(v) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="${v.name}">
  <defs>
    <linearGradient id="bg-${v.id}" x1="0" y1="0" x2="1" y2="1">
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
    <circle cx="256" cy="248" r="190" fill="${v.halo}" opacity="${v.haloOpacity}"/>
    <circle cx="108" cy="96" r="56" fill="#FFFFFF" opacity="0.10"/>
    <circle cx="414" cy="436" r="82" fill="#000000" opacity="0.05"/>
    <circle cx="256" cy="580" r="300" fill="#000000" opacity="0.05"/>
    ${head(v)}
    <rect x="4" y="4" width="504" height="504" rx="112" fill="none" stroke="#FFFFFF" stroke-opacity="0.16" stroke-width="2"/>
  </g>
</svg>
`;
}

function headSvg(v) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512" role="img" aria-label="${v.name} 头部">
  <defs>
    <linearGradient id="iris-${v.id}" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${v.eyeB}"/>
      <stop offset="1" stop-color="${v.eyeA}"/>
    </linearGradient>
  </defs>
  ${head(v)}
</svg>
`;
}

for (const v of variants) {
  writeFileSync(join(OUT, `app_${v.id}.svg`), appSvg(v), 'utf8');
  writeFileSync(join(OUT, `head_${v.id}.svg`), headSvg(v), 'utf8');
}

writeFileSync(
  join(OUT, 'variants.json'),
  JSON.stringify(variants.map(({ id, name, tag, desc }) => ({ id, name, tag, desc })), null, 2),
  'utf8'
);

console.log(`generated ${variants.length * 2} svg files in ${OUT}`);
