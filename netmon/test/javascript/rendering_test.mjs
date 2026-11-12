// Exercise the real renderers in a real browser without Rails or npm test dependencies.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const app = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const browser = [process.env.BROWSER_BIN, "/usr/bin/google-chrome", "/usr/bin/google-chrome-stable", "/usr/bin/chromium",
  "C:/Program Files/Google/Chrome/Application/chrome.exe", "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"]
  .find((candidate) => candidate && existsSync(candidate));
assert.ok(browser, "Chrome/Edge is required; set BROWSER_BIN to its executable");
const directory = mkdtempSync(join(tmpdir(), "netmon-rendering-"));
try {
  const moduleURL = (source) => "data:text/javascript;base64," + Buffer.from(source).toString("base64");
  const domURL = moduleURL(readFileSync(join(app, "app/javascript/netmon/dom.js"), "utf8"));
  const renderingURL = moduleURL(readFileSync(join(app, "app/javascript/netmon/dashboard_rendering.js"), "utf8").replace('"./dom.js"', JSON.stringify(domURL)));
  const dashboardURL = moduleURL(readFileSync(join(app, "app/javascript/netmon/dashboard.js"), "utf8")
    .replace('"./dom.js"', JSON.stringify(domURL)).replace('"./dashboard_rendering.js"', JSON.stringify(renderingURL)));
  const imports = `import { element, hostLink, renderPanelList } from ${JSON.stringify(domURL)};\nimport { renderConnectionRow, renderDrilldownRow } from ${JSON.stringify(renderingURL)};\nimport { initializeDashboard } from ${JSON.stringify(dashboardURL)};`;
  const tests = `
    const check = (condition, message) => { if (!condition) throw Error(message); };
    const hostile = '<img src=x onerror="globalThis.pwned=true">';
    const quoted = '\" onmouseover=\"globalThis.pwned=true';
    const row = renderConnectionRow({ proto: hostile, device_id: 1, device_name: quoted,
      src_ip: hostile, dst_ip: hostile, src_port: 123, dst_port: 443, last_domain: hostile,
      last_domain_observed_at: quoted, rdns_name: hostile, whois_name: hostile, whois_raw_line: quoted,
      state: hostile, flags: hostile, anomaly_reasons: [hostile], seen_age: hostile }, String);
    document.body.append(row);
    check(!row.querySelector('img, script'), 'Connection metadata became markup');
    check(row.querySelector('input').value === quoted, 'Device name changed');
    check(!row.querySelector('input').hasAttribute('onmouseover'), 'Attribute injection');
    check(row.querySelector('[data-col=source] a').getAttribute('href') === '/remote_hosts/' + encodeURIComponent(hostile), 'IP path not encoded');
    check(row.querySelector('[data-col=domain] a').textContent === hostile, 'Domain not literal text');
    check(!row.querySelector('[data-col=whois]').hasAttribute('onmouseover'), 'WHOIS attribute injection');
    const drilldown = renderDrilldownRow({ device: hostile, dst_ip: hostile, reason: hostile,
      proto: hostile, timestamp: hostile, ips: [hostile], count: hostile, first_seen_at: hostile }, String, 'fallback');
    document.body.append(drilldown);
    check(!drilldown.querySelector('img,script'), 'Drilldown metadata became markup');
    check(drilldown.textContent.includes(hostile), 'Drilldown lost literal text');
    const panels = document.createElement('ul');
    renderPanelList(panels, [hostile, element('span', {}, hostile), hostLink(hostile)]);
    document.body.append(panels);
    check(!panels.querySelector('img,script'), 'Panel metadata became markup');
    check(panels.children.length === 3 && panels.firstChild.textContent === hostile, 'Panel rendering failed');
    check(!globalThis.pwned, 'Injected JavaScript executed');
    const tableBody = element('tbody', { id: 'connections-body' });
    document.body.append(element('table', {}, tableBody));
    const topDevices = element('ul', { id: 'panel-top-devices-egress' });
    const incidents = element('ul', { id: 'panel-recent-incidents' });
    document.body.append(topDevices, incidents, element('div', { id: 'columns-toggle' }));
    globalThis.fetch = async (url) => ({ json: async () => String(url).startsWith('/connections')
      ? { data: [{ src_ip: '10.0.0.20', dst_ip: '203.0.113.8', device_id: 1, device_name: hostile }] }
      : String(url).startsWith('/dashboard')
        ? { top_devices_egress: [{ label: hostile, total_uplink: 10 }], recent_incidents: [{ id: 1, device: hostile, codes: hostile }] }
        : {} });
    initializeDashboard();
    await new Promise((resolve) => setTimeout(resolve, 0));
    check(tableBody.querySelector('input')?.value === hostile, 'Dashboard polling did not populate rows');
    check(topDevices.textContent.includes(hostile) && !topDevices.querySelector('img'), 'Device panel unsafe or missing');
    check(incidents.textContent.includes(hostile) && !incidents.querySelector('img'), 'Incident panel unsafe or missing');
    document.dispatchEvent(new Event('turbo:before-cache'));
    document.documentElement.dataset.result = 'passed';
  `;
  const html = join(directory, "test.html");
  writeFileSync(html, `<!doctype html><html><body><script type="module">${imports}\ntry {${tests}} catch (error) { document.documentElement.dataset.result = 'failed'; document.body.textContent = error.stack; }</script></body></html>`);
  const output = execFileSync(browser, ["--headless", "--disable-gpu", "--no-first-run", "--disable-extensions",
    "--disable-background-networking", `--user-data-dir=${join(directory, "profile")}`, "--dump-dom", pathToFileURL(html).href],
  { encoding: "utf8", timeout: 30000, maxBuffer: 2 * 1024 * 1024, windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  assert.match(output, /data-result="passed"/, output);
  console.log("Dashboard rendering browser checks passed (connections, attributes, URLs, drilldowns and panels).");
} finally {
  // Delete only the private temporary directory created above.
  assert.ok(resolve(directory).startsWith(resolve(tmpdir()) + (process.platform === "win32" ? "\\" : "/")));
  assert.ok(dirname(directory) === tmpdir() && directory.includes("netmon-rendering-"));
  rmSync(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 100 });
}
