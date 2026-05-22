// Headless verification: drive the debugger UI and screenshot key states.
import puppeteer from "puppeteer-core";

const URL = "http://localhost:5173";
const OUT = "/tmp";
const errors = [];

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const browser = await puppeteer.launch({
  executablePath: "/usr/bin/google-chrome",
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
  await page.waitForFunction(() => document.body.innerText.includes("step 1"), {
    timeout: 60000,
  });
  await sleep(500);

  // --- forward step ---
  await shot("1_forward");
  const fwdText = await page.$eval("code", (el) => el.textContent);
  check("first step shows a forward IR statement", /get_shared_data_field/.test(fwdText));

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

  // --- editable inputs: change c.v and confirm the trace re-runs ---
  const before = await page.$eval("body", (b) => b.innerText);
  const num = await page.$('input[type="number"]');
  await num.click({ clickCount: 3 });
  await page.keyboard.type("7");
  await sleep(2500);
  const after = await page.$eval("body", (b) => b.innerText);
  check("editing an input re-ran the trace", before !== after);
  // bump!(7) = 49, gradient 14
  const has49 = after.includes("49");
  check("new input produced a fresh primal value (49)", has49);
  await shot("5_edited");

  // --- IR pipeline tab ---
  await page.click("::-p-text(IR pipeline)");
  await sleep(500);
  await shot("6_pipeline");
  const pipeline = await page.$eval("body", (b) => b.innerText);
  check("IR pipeline viewer shows stage tabs", pipeline.includes("Optimised"));

  // --- vector-pair example: the output-side fdata / rdata split ---
  await page.click("::-p-text(Vector + scalar output)");
  await page.waitForFunction(() => document.body.innerText.includes("vpair(x)"), {
    timeout: 30000,
  });
  await sleep(1200);
  await shot("7_vector_pair");
  const vp = await page.$eval("body", (b) => b.innerText);
  // innerText applies CSS text-transform, so the panel heading is upper-cased.
  check("seed panel shows the output cotangent", vp.includes("OUTPUT COTANGENT"));
  check(
    "cotangent split shows the fdata and rdata halves",
    vp.includes("fdata") && vp.includes("rdata"),
  );
  check(
    "split shows the tuple output type",
    vp.includes("Tuple{Vector{Float64}, Float64}"),
  );

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
