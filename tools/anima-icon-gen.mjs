// 调用本机 ComfyUI + Anima Turbo 生成一张二次元底图。
// 用法：node anima-icon-gen.mjs "<英文提示词>" "<输出 png 路径>"
import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';
import { pathToFileURL } from 'node:url';

const prompt = process.argv[2];
const out = process.argv[3];
if (!prompt || !out) {
  console.error('用法: node anima-icon-gen.mjs "<prompt>" "<out.png>"');
  process.exit(2);
}

const wrapperUrl = pathToFileURL('C:/Users/rinnki/.dsh/plugins-data/aurabot/local/image.mjs').href;
const { default: generate } = await import(wrapperUrl);

const log = {
  info: (...args) => console.log('[anima]', ...args),
  warn: (...args) => console.warn('[anima]', ...args)
};

mkdirSync(dirname(out), { recursive: true });
const buf = await generate({
  prompt,
  size: '1024x1024',
  outDir: 'C:/da/demos/icons/anima/refs',
  log
});
writeFileSync(out, buf);
console.log(`[anima] saved ${out} (${Math.round(buf.length / 1024)} KB)`);
