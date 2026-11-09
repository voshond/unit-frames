import { chromium } from "playwright-core";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const VIEWER = "classic-wow-model-viewer/dist/index.js";
const DEFAULT_CDN = "https://jollygrin.github.io/turtle-wow-model-viewer";
const BROWSERS = path.join(homedir(), ".cache", "ms-playwright");
const TYPES = { ".js": "text/javascript", ".html": "text/html" };

const usage = () => {
	console.error("usage: node capture.mjs <race> <male|female> <out.png> [--hair N] [--size N] [--cdn URL]");
	process.exit(1);
};

const parseArgs = (argv) => {
	const [race, gender, out, ...rest] = argv;
	if (!race || !gender || !out) usage();
	const options = { race, gender, out, hair: 1, size: 256, cdn: process.env.PORTRAIT_CDN ?? DEFAULT_CDN };
	for (let index = 0; index < rest.length; index += 2) {
		const key = rest[index].replace(/^--/, "");
		if (!(key in options) || rest[index + 1] === undefined) usage();
		options[key] = ["hair", "size"].includes(key) ? Number(rest[index + 1]) : rest[index + 1];
	}
	return options;
};

const findChrome = () => {
	if (process.env.CHROME) return process.env.CHROME;
	const shells = existsSync(BROWSERS) ? readdirSync(BROWSERS).filter((name) => name.startsWith("chromium_headless_shell-")).sort() : [];
	for (const shell of shells.reverse()) {
		for (const build of readdirSync(path.join(BROWSERS, shell))) {
			const binary = path.join(BROWSERS, shell, build, "chrome-headless-shell");
			if (existsSync(binary)) return binary;
		}
	}
	return undefined;
};

const withHairstyle = (source, hair) => {
	const patched = source.replace("a.groups,\n    5,", `a.groups,\n    ${hair},`);
	if (patched === source) throw new Error(`${VIEWER} changed: can't set the hairstyle`);
	return patched;
};

const serve = (page, hair) => page.route("http://capture/**", (route) => {
	const pathname = new URL(route.request().url()).pathname;
	const file = path.join(ROOT, pathname);
	if (!file.startsWith(ROOT) || !existsSync(file)) return route.fulfill({ status: 404 });
	const body = pathname.endsWith(VIEWER) ? withHairstyle(readFileSync(file, "utf8"), hair) : readFileSync(file);
	return route.fulfill({ body, contentType: TYPES[path.extname(file)] ?? "application/octet-stream" });
});

const options = parseArgs(process.argv.slice(2));
const browser = await chromium.launch({
	executablePath: findChrome(),
	args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"],
});
const work = mkdtempSync(path.join(tmpdir(), "portrait-"));

try {
	const page = await browser.newPage({ viewport: { width: options.size, height: options.size } });
	page.on("pageerror", (error) => console.error(error.message));
	await serve(page, options.hair);
	const query = new URLSearchParams({ cdn: options.cdn, race: options.race, gender: options.gender });
	await page.goto(`http://capture/page.html?${query}`);
	await page.waitForFunction(() => window.ready, null, { timeout: 60000 });

	const shots = {};
	for (const [name, color] of [["black", 0x000000], ["white", 0xffffff]]) {
		await page.evaluate((value) => window.setBackground(value), color);
		await page.waitForTimeout(500);
		shots[name] = path.join(work, `${name}.png`);
		await page.screenshot({ path: shots[name] });
	}

	execFileSync("magick", [
		shots.black,
		"(", shots.black, shots.white, "-compose", "difference", "-composite", "-colorspace", "gray", "-negate", ")",
		"-alpha", "off", "-compose", "copy_opacity", "-composite", options.out,
	]);
	console.log(options.out);
} finally {
	await browser.close();
	rmSync(work, { recursive: true, force: true });
}
