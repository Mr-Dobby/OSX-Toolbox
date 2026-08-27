import Foundation

/// Self-contained HTML/CSS/JS page (no external network requests, no CDNs)
/// that polls `/stats` on the same local server every 2 seconds.
let dashboardHTMLPage = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>RALBE OSX Toolbox — Live Stats</title>
<style>
  :root { color-scheme: dark; }
  body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #111318; color: #f0f0f2; margin: 0; padding: 32px; }
  h1 { font-size: 20px; font-weight: 600; margin-bottom: 4px; }
  h3 { margin: 20px 0 10px; font-size: 15px; color: #c7c7d1; }
  .sub { color: #9a9aa5; font-size: 13px; margin-bottom: 24px; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; }
  .card { background: #1b1e27; border-radius: 12px; padding: 16px 18px; }
  .card h2 { font-size: 12px; text-transform: uppercase; letter-spacing: 0.04em; color: #9a9aa5; margin: 0 0 8px; }
  .value { font-size: 24px; font-weight: 700; }
  .value.small { font-size: 15px; font-weight: 600; }
  .bar-track { background: #2a2e3a; border-radius: 6px; height: 7px; margin-top: 8px; overflow: hidden; }
  .bar-fill { height: 100%; border-radius: 6px; background: linear-gradient(90deg, #4f9dff, #6ee7b7); transition: width 0.4s ease; }
  .row { display: flex; justify-content: space-between; font-size: 12px; color: #c7c7d1; margin-top: 4px; }
  code { color: #8fd0ff; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { text-align: left; padding: 4px 6px; }
  th { color: #9a9aa5; font-weight: 500; font-size: 11px; text-transform: uppercase; }
  tr:nth-child(even) { background: #21242e; }
  .disk-row { margin-bottom: 10px; }
  .disk-row .row { margin-top: 2px; }
</style>
</head>
<body>
  <h1 id="host">RALBE OSX Toolbox</h1>
  <div class="sub">Live device statistics · updates every 2s · <span id="statusValue">connecting…</span></div>

  <h3>System</h3>
  <div class="grid">
    <div class="card">
      <h2>Model</h2>
      <div class="value small" id="modelValue">–</div>
      <div class="row"><span id="osValue"></span></div>
    </div>
    <div class="card">
      <h2>CPU</h2>
      <div class="value" id="cpuValue">–</div>
      <div class="bar-track"><div class="bar-fill" id="cpuBar" style="width:0%"></div></div>
      <div class="row"><span id="cpuBrandValue"></span></div>
    </div>
    <div class="card">
      <h2>Load Average</h2>
      <div class="value small" id="loadValue">–</div>
      <div class="row"><span id="thermalValue"></span></div>
    </div>
    <div class="card">
      <h2>Memory</h2>
      <div class="value" id="memValue">–</div>
      <div class="bar-track"><div class="bar-fill" id="memBar" style="width:0%"></div></div>
    </div>
    <div class="card">
      <h2>Swap</h2>
      <div class="value" id="swapValue">–</div>
      <div class="bar-track"><div class="bar-fill" id="swapBar" style="width:0%"></div></div>
    </div>
    <div class="card">
      <h2>Uptime</h2>
      <div class="value" id="uptimeValue">–</div>
      <div class="row"><span id="runningAppsValue"></span></div>
    </div>
    <div class="card">
      <h2>Battery</h2>
      <div class="value" id="batteryValue">–</div>
      <div class="row"><span id="batteryState"></span></div>
      <div class="row"><span id="batteryHealthValue"></span></div>
    </div>
    <div class="card" id="disksCard">
      <h2>Disks</h2>
    </div>
  </div>

  <h3>Network</h3>
  <div class="grid">
    <div class="card">
      <h2>WiFi Network</h2>
      <div class="value small" id="wifiValue">–</div>
    </div>
    <div class="card">
      <h2>Local IP</h2>
      <div class="value small" id="ipValue">–</div>
    </div>
    <div class="card">
      <h2>Public IP</h2>
      <div class="value small" id="publicIpValue">–</div>
    </div>
    <div class="card">
      <h2>IPv6</h2>
      <div class="value small" id="ipv6Value">–</div>
    </div>
  </div>

  <h3>Processes</h3>
  <div class="grid">
    <div class="card">
      <h2>Top CPU</h2>
      <table><thead><tr><th>Name</th><th>CPU%</th><th>Mem%</th></tr></thead><tbody id="topCpuBody"></tbody></table>
    </div>
    <div class="card">
      <h2>Top Memory</h2>
      <table><thead><tr><th>Name</th><th>CPU%</th><th>Mem%</th></tr></thead><tbody id="topMemBody"></tbody></table>
    </div>
  </div>

<script>
function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return (d > 0 ? d + "d " : "") + h + "h " + m + "m";
}

function renderProcessTable(elementId, processes) {
  const body = document.getElementById(elementId);
  body.innerHTML = "";
  (processes || []).forEach(p => {
    const tr = document.createElement("tr");
    tr.innerHTML = "<td>" + p.name + "</td><td>" + p.cpu.toFixed(1) + "</td><td>" + p.mem.toFixed(1) + "</td>";
    body.appendChild(tr);
  });
}

function renderDisks(disks) {
  const card = document.getElementById("disksCard");
  card.innerHTML = "<h2>Disks</h2>";
  (disks || []).forEach(d => {
    const pct = d.totalGB > 0 ? (d.usedGB / d.totalGB) * 100 : 0;
    const wrap = document.createElement("div");
    wrap.className = "disk-row";
    wrap.innerHTML = "<div class=\\"row\\"><span>" + d.name + "</span><span>" + d.usedGB.toFixed(0) + " / " + d.totalGB.toFixed(0) + " GB</span></div>" +
      "<div class=\\"bar-track\\"><div class=\\"bar-fill\\" style=\\"width:" + pct + "%\\"></div></div>";
    card.appendChild(wrap);
  });
}

async function refresh() {
  try {
    const res = await fetch("/stats", { cache: "no-store" });
    const s = await res.json();

    document.title = s.cpuPercent.toFixed(0) + "% CPU · RALBE OSX Toolbox";
    document.getElementById("host").textContent = s.hostName || "RALBE OSX Toolbox";
    document.getElementById("statusValue").textContent = "last updated " + new Date().toLocaleTimeString();

    document.getElementById("modelValue").textContent = s.modelIdentifier || "–";
    document.getElementById("osValue").textContent = "macOS " + (s.osVersion || "");

    document.getElementById("cpuValue").textContent = s.cpuPercent.toFixed(1) + "%";
    document.getElementById("cpuBar").style.width = Math.min(100, s.cpuPercent) + "%";
    document.getElementById("cpuBrandValue").textContent = (s.cpuBrand || "") + " · " + s.cpuCoreCount + " cores";

    const loads = s.loadAverage || [0, 0, 0];
    document.getElementById("loadValue").textContent = loads.map(l => l.toFixed(2)).join(" / ");
    document.getElementById("thermalValue").textContent = "Thermal: " + (s.thermalState || "Unknown");

    const memPct = s.memoryTotalGB > 0 ? (s.memoryUsedGB / s.memoryTotalGB) * 100 : 0;
    document.getElementById("memValue").textContent = s.memoryUsedGB.toFixed(1) + " / " + s.memoryTotalGB.toFixed(1) + " GB";
    document.getElementById("memBar").style.width = memPct + "%";

    const swapPct = s.swapTotalGB > 0 ? (s.swapUsedGB / s.swapTotalGB) * 100 : 0;
    document.getElementById("swapValue").textContent = s.swapTotalGB > 0 ? (s.swapUsedGB.toFixed(1) + " / " + s.swapTotalGB.toFixed(1) + " GB") : "None";
    document.getElementById("swapBar").style.width = swapPct + "%";

    document.getElementById("uptimeValue").textContent = formatUptime(s.uptimeSeconds);
    document.getElementById("runningAppsValue").textContent = (s.runningAppsCount || 0) + " apps running";

    document.getElementById("batteryValue").textContent = s.batteryPercent + "%";
    document.getElementById("batteryState").textContent = s.batteryCharging ? "Charging" : (s.acConnected ? "AC Connected" : "On Battery");
    document.getElementById("batteryHealthValue").textContent = (s.batteryCondition || "Unknown") + " · " + (s.batteryCycleCount || 0) + " cycles";

    renderDisks(s.disks);

    document.getElementById("wifiValue").textContent = s.wifiSSID || "Not connected";
    document.getElementById("ipValue").textContent = (s.localIPs && s.localIPs.length > 0) ? s.localIPs.join(", ") : "–";
    document.getElementById("publicIpValue").textContent = s.publicIP || "–";
    document.getElementById("ipv6Value").textContent = (s.localIPv6s && s.localIPv6s.length > 0) ? s.localIPv6s.join(", ") : "Not available";

    renderProcessTable("topCpuBody", s.topCPUProcesses);
    renderProcessTable("topMemBody", s.topMemProcesses);
  } catch (e) {
    document.getElementById("statusValue").textContent = "connection lost - retrying…";
  }
}

refresh();
setInterval(refresh, 2000);
</script>
</body>
</html>
"""
