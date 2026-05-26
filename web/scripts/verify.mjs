// Headless verification: drive the debugger UI and screenshot key states.
import { existsSync } from "node:fs";
import puppeteer from "puppeteer-core";

const URL = process.env.VERIFY_URL ?? "http://localhost:5173";
const OUT = "/tmp";
const errors = [];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function findBrowserExecutable() {
  const envPath =
    process.env.PUPPETEER_EXECUTABLE_PATH ??
    process.env.CHROME_BIN ??
    process.env.CHROMIUM_BIN;
  if (envPath) return envPath;

  const candidates = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/opt/google/chrome/chrome",
    "/opt/homebrew/bin/chromium",
    "/opt/homebrew/bin/google-chrome",
  ];
  return candidates.find((path) => existsSync(path));
}

const executablePath = findBrowserExecutable();
if (!executablePath) {
  throw new Error(
    "No Chrome/Chromium executable found. Set PUPPETEER_EXECUTABLE_PATH, " +
      "CHROME_BIN, or CHROMIUM_BIN to run web/scripts/verify.mjs.",
  );
}

const browser = await puppeteer.launch({
  executablePath,
  headless: "new",
  args: ["--no-sandbox", "--disable-gpu"],
});
const page = await browser.newPage();
await page.setViewport({ width: 1680, height: 1050, deviceScaleFactor: 1 });
page.on("pageerror", (e) => errors.push(`pageerror: ${e.message}`));
page.on("console", (m) => {
  if (m.type() === "error") errors.push(`console.error: ${m.text()}`);
});

async function shot(name) {
  await page.screenshot({ path: `${OUT}/verify_${name}.png` });
  console.log(`  screenshot -> verify_${name}.png`);
}

function check(label, ok) {
  console.log(`  [${ok ? "PASS" : "FAIL"}] ${label}`);
  if (!ok) errors.push(`check failed: ${label}`);
}

try {
  console.log("loading app…");
  await page.goto(URL, { waitUntil: "networkidle0", timeout: 60000 });
  await page.waitForFunction(() => document.body.innerText.includes("step 1 ·"), {
    timeout: 60000,
  });
  await sleep(500);

  // --- forward step ---
  await shot("1_forward");
  const fwdText = await page.$eval("code", (el) => el.textContent);
  check("first step shows a forward IR statement", /get_shared_data_field/.test(fwdText));
  const initialBody = await page.$eval("body", (b) => b.innerText);
  check("tape summary is present in the two-column layout", initialBody.includes("TAPE"));
  check("result panel is removed", !initialBody.includes("RESULT"));
  check("trace notes panel is removed", !initialBody.includes("Static baked trace"));
  check(
    "program card shows the differentiated Julia argument, not input JSON",
    initialBody.includes("(2.0, [1.0, 3.0, 5.0])") && !initialBody.includes('{"x1"'),
  );
  check(
    "program card shows the argument type, not the full AD signature",
    initialBody.includes("Tuple{Float64, Vector{Float64}}") &&
      !initialBody.includes("Tuple{typeof(foo)"),
  );

  // --- step into the reverse pass via the timeline ---
  const revSel = 'button[title*="· reverse ·"]';
  await page.waitForSelector(revSel, { timeout: 5000 });
  await page.click(revSel);
  await sleep(400);
  await shot("2_reverse");
  const revBadge = await page.$eval("body", (b) => b.innerText.includes("REVERSE"));
  check("reverse step shows REVERSE badge", revBadge);

  // --- switch to the mutation example, jump to a restore step ---
  await page.click("::-p-text(In-place mutation)");
  await page.waitForFunction(() => document.body.innerText.includes("bump!"), {
    timeout: 30000,
  });
  await sleep(800);
  await shot("3_mutation");

  const restoreSel = 'button[title*="· restore ·"]';
  const hasRestore = (await page.$(restoreSel)) !== null;
  check("mutation trace has a restore step", hasRestore);
  if (hasRestore) {
    await page.click(restoreSel);
    await sleep(400);
    await shot("4_restore");
    const restoreBadge = await page.$eval("body", (b) =>
      b.innerText.includes("RESTORE"),
    );
    check("restore step shows RESTORE badge", restoreBadge);
  }

  // --- static trace mode: no live Julia backend or numeric input editor ---
  const numberInputs = await page.$$('input[type="number"]');
  check("static viewer has no numeric input editor", numberInputs.length === 0);

  // --- IR pipeline tab ---
  await page.click("::-p-text(IR pipeline)");
  await sleep(500);
  await shot("5_pipeline");
  const pipeline = await page.$eval("body", (b) => b.innerText);
  check("IR pipeline viewer shows stage tabs", pipeline.includes("Optimised"));

  // --- vector-pair example: baked trace with output-side fdata / rdata split ---
  await page.click("::-p-text(Vector + scalar output)");
  await page.waitForFunction(() => document.body.innerText.includes("vpair(x)"), {
    timeout: 30000,
  });
  await sleep(1200);
  await shot("6_vector_pair");
  const vp = await page.$eval("body", (b) => b.innerText);
  check("vector-pair trace loaded", vp.includes("vpair(x) = (copy(x), sum(x))"));
  check("vector-pair still shows tape summary", vp.includes("TAPE"));

  // --- branch example: stack 1 records the chosen forward block ---
  await page.click("::-p-text(Branching control flow)");
  await page.waitForFunction(() => document.body.innerText.includes("branchy(x)"), {
    timeout: 30000,
  });
  const pushSel = 'button[title*="__push_blk_stack"]';
  await page.waitForSelector(pushSel, { timeout: 5000 });
  await page.click(pushSel);
  await sleep(400);
  await shot("7_branch_stack_push");
  const branchPush = await page.$eval("body", (b) => b.innerText);
  check("branch trace loaded", branchPush.includes("branchy(x) = x > 0 ? x * x : sin(x)"));
  check("branch push step leaves block stack s1 non-empty", branchPush.includes("s1:1"));

  const popSel = 'button[title*="__pop_blk_stack"]';
  await page.waitForSelector(popSel, { timeout: 5000 });
  await page.click(popSel);
  await sleep(400);
  await shot("8_branch_stack_pop");
  const branchPop = await page.$eval("body", (b) => b.innerText);
  check("branch reverse step pops block stack s1", branchPop.includes("s1:0"));

  console.log(`\nconsole/page errors: ${errors.length}`);
  errors.forEach((e) => console.log("  - " + e));
  process.exitCode = errors.length === 0 ? 0 : 1;
} catch (e) {
  console.error("VERIFY ERROR:", e.message);
  await shot("error");
  process.exitCode = 1;
} finally {
  await browser.close();
}
