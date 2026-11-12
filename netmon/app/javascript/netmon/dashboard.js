import { element as el, hostLink, renderPanelList } from "./dom.js";
import { renderConnectionRow, renderDrilldownRow } from "./dashboard_rendering.js";

let disposeDashboard;

export function initializeDashboard() {
    disposeDashboard?.();
    const listeners = new AbortController();
    const listen = (target, type, callback) => target.addEventListener(type, callback, { signal: listeners.signal });
    const body = document.getElementById("connections-body");
    if (!body) return;
    const pageInfoEl = document.getElementById("connections-page-info");
    const prevBtn = document.getElementById("connections-prev");
    const nextBtn = document.getElementById("connections-next");
    const perPageSelect = document.getElementById("connections-per-page");
    const perPageStorageKey = "netmon.connections.per_page";
    let collectorIsStale = false;
    let currentPage = 1;
    let totalRows = 0;
    let inFlightConnections = false;
    let inFlightMetrics = false;
    let inFlightStatSeries = false;
    let inFlightGraphSeries = false;
    let inFlightSystemSeries = false;
    let inFlightTopPanels = false;
    const pollControllers = {};

    function shouldPoll(force = false) {
      return force || !document.hidden;
    }

    function beginPollRequest(key) {
      const controller = new AbortController();
      pollControllers[key] = controller;
      return controller;
    }

    function endPollRequest(key, controller) {
      if (pollControllers[key] === controller) {
        delete pollControllers[key];
      }
    }

    function abortAllPollRequests() {
      Object.values(pollControllers).forEach((controller) => controller.abort());
    }

    function formatBytes(value) {
      if (value == null) return "--";
      const units = ["B", "KiB", "MiB", "GiB", "TiB"];
      let n = Number(value);
      let idx = 0;
      while (n >= 1024 && idx < units.length - 1) {
        n /= 1024;
        idx += 1;
      }
      const formatted = idx === 0 ? `${Math.round(n)} ${units[idx]}` : `${n.toFixed(1)} ${units[idx]}`;
      return formatted;
    }

    function renderRow(conn) { return renderConnectionRow(conn, formatBytes); }

    function buildConnectionsQuery() {
      const params = new URLSearchParams();
      const form = document.getElementById("connections-filter");
      if (!form) return "";
      const src = form.querySelector("input[name='src_ip']")?.value.trim();
      const dst = form.querySelector("input[name='dst_ip']")?.value.trim();
      const dport = form.querySelector("input[name='dport']")?.value.trim();
      const proto = form.querySelector("input[name='proto']")?.value.trim();
      const hiddenStates = Array.from(form.querySelectorAll("input[name='hide_states[]']:checked")).map((input) => input.value);
      const onlyNew = form.querySelector("input[name='only_new']")?.checked;
      const includeStale = form.querySelector("input[name='include_stale']")?.checked;
      const minScore = form.querySelector("select[name='min_score']")?.value;
      const sort = form.querySelector("input[name='sort']")?.value;
      const dir = form.querySelector("input[name='dir']")?.value;

      if (src) params.set("src_ip", src);
      if (dst) params.set("dst_ip", dst);
      if (dport) params.set("dport", dport);
      if (proto) params.set("proto", proto);
      hiddenStates.forEach((state) => params.append("hide_states[]", state));
      if (onlyNew) params.set("only_new", "true");
      if (includeStale) params.set("include_stale", "true");
      if (minScore) params.set("min_score", minScore);
      if (sort) params.set("sort", sort);
      if (dir) params.set("dir", dir);
      params.set("page", currentPage);
      params.set("per_page", perPageSelect ? perPageSelect.value : "200");

      const query = params.toString();
      return query ? `?${query}` : "";
    }

    function refresh(force = false) {
      if (!shouldPoll(force)) return;
      if (inFlightConnections) return;
      if (document.activeElement && document.activeElement.classList.contains("device-name-input")) {
        return;
      }
      inFlightConnections = true;
      const controller = beginPollRequest("connections");
      const query = buildConnectionsQuery();
      fetch(`/connections.json${query}`, { signal: controller.signal })
        .then((resp) => resp.json())
        .then((payload) => {
          const data = Array.isArray(payload) ? payload : payload.data || [];
          const meta = payload.meta || {};
          totalRows = meta.total || data.length;
          const perPage = Number(meta.per_page || (perPageSelect ? perPageSelect.value : 200));
          const totalPages = perPage > 0 ? Math.max(1, Math.ceil(totalRows / perPage)) : 1;
          if (currentPage > totalPages) {
            currentPage = totalPages;
          }
          if (pageInfoEl) {
            pageInfoEl.textContent = `Page ${currentPage} of ${totalPages} (${totalRows} total)`;
          }
          if (prevBtn) prevBtn.disabled = currentPage <= 1;
          if (nextBtn) nextBtn.disabled = currentPage >= totalPages;
          body.replaceChildren(...data.map(renderRow));
          applyColumnVisibility();
        })
        .catch((error) => {
          if (error?.name !== "AbortError") {
            // no-op: transient poll failures should not disrupt UI
          }
        })
        .finally(() => {
          inFlightConnections = false;
          endPollRequest("connections", controller);
        });
    }

    if (perPageSelect) {
      const savedPerPage = localStorage.getItem(perPageStorageKey);
      if (savedPerPage) perPageSelect.value = savedPerPage;
    }

    if (prevBtn) {
      listen(prevBtn, "click", () => {
        if (currentPage > 1) {
          currentPage -= 1;
          refresh(true);
        }
      });
    }

    if (nextBtn) {
      listen(nextBtn, "click", () => {
        currentPage += 1;
        refresh(true);
      });
    }

    if (perPageSelect) {
      listen(perPageSelect, "change", () => {
        localStorage.setItem(perPageStorageKey, perPageSelect.value);
        currentPage = 1;
        refresh(true);
      });
    }

    const filterForm = document.getElementById("connections-filter");
    if (filterForm) {
      listen(filterForm, "submit", (event) => {
        event.preventDefault();
        currentPage = 1;
        refresh(true);
      });
    }

    refresh(true);
    const connectionsPollTimer = setInterval(() => refresh(), 2000);

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content;
    let pendingSave = null;

    function saveDeviceName(input) {
      const deviceId = input.dataset.deviceId;
      if (!deviceId) return;
      if (!csrfToken) return;

      const name = input.value.trim();
      if (pendingSave) clearTimeout(pendingSave);
      pendingSave = setTimeout(() => {
        fetch(`/devices/${deviceId}`, {
          method: "PATCH",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": csrfToken,
            "Accept": "application/json"
          },
          body: JSON.stringify({ device: { name } })
        }).catch(() => {});
      }, 200);
    }

    listen(body, "change", (event) => {
      const target = event.target;
      if (target && target.classList.contains("device-name-input")) {
        saveDeviceName(target);
      }
    });

    listen(body, "keydown", (event) => {
      const target = event.target;
      if (!target || !target.classList.contains("device-name-input")) return;
      if (event.key === "Enter") {
        event.preventDefault();
        target.blur();
      }
    });

    listen(body, "click", (event) => {
      const target = event.target;
      if (!target || !target.classList.contains("allow-port-btn")) return;
      const deviceId = target.dataset.deviceId;
      const port = target.dataset.port;
      if (!deviceId || !port || !csrfToken) return;
      fetch("/allowlist_rules", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": csrfToken,
          "Accept": "application/json"
        },
        body: JSON.stringify({ allowlist_rule: { kind: "device_port", value: port, device_id: deviceId } })
      }).catch(() => {});
    });

    const loadavgEl = document.getElementById("metric-loadavg");
    const collectorEl = document.getElementById("metric-collector");
    const collectorWarningEl = document.getElementById("collector-warning");
    const memEl = document.getElementById("metric-mem");
    const ifacesEl = document.getElementById("metric-ifaces");
    const interfacesInput = document.getElementById("metric-interfaces");
    const newDstEl = document.getElementById("metric-new-dst");
    const uniqueDportsEl = document.getElementById("metric-unique-dports");
    const uplinkBytesEl = document.getElementById("metric-uplink-bytes");
    const newAsnsEl = document.getElementById("metric-new-asns");
    const anomaliesEl = document.getElementById("metric-anomalies");
    const metricsUpdatedEl = document.getElementById("metrics-updated");
    const detailEl = document.getElementById("metric-detail");
    const detailTitleEl = document.getElementById("metric-detail-title");
    const detailBodyEl = document.getElementById("metric-detail-body");
    const rarePortsList = document.getElementById("panel-rare-ports");
    const drilldownOverlay = document.getElementById("drilldown-overlay");
    const drilldownClose = document.getElementById("drilldown-close");
    const drilldownTitle = document.getElementById("drilldown-title");
    const drilldownWindow = document.getElementById("drilldown-window");
    const drilldownGenerated = document.getElementById("drilldown-generated");
    const drilldownBody = document.getElementById("drilldown-body");
    const drilldownWarning = document.getElementById("drilldown-warning");
    const drilldownCopyPorts = document.getElementById("drilldown-copy-ports");
    const drilldownCopyIps = document.getElementById("drilldown-copy-ips");
    const drilldownPrev = document.getElementById("drilldown-prev");
    const drilldownNext = document.getElementById("drilldown-next");
    const drilldownPageEl = document.getElementById("drilldown-page");
    const chartModal = document.getElementById("chart-modal");
    const chartModalClose = document.getElementById("chart-modal-close");
    const chartModalTitle = document.getElementById("chart-modal-title");
    const chartModalCanvas = document.getElementById("chart-modal-canvas");

    let lastAnalytics = null;

    function closeDrilldown() {
      if (drilldownOverlay) drilldownOverlay.classList.add("hidden");
    }

    const drilldownState = { kind: null, window: null, title: null, options: {}, page: 1, totalPages: 1 };

    function openDrilldown(kind, window, title, options = {}) {
      if (!drilldownOverlay) return;
      drilldownState.kind = kind;
      drilldownState.window = window;
      drilldownState.title = title;
      drilldownState.options = options;
      drilldownState.page = 1;
      if (drilldownTitle) drilldownTitle.textContent = title;
      if (drilldownWindow) drilldownWindow.textContent = `Window: ${window}`;
      if (drilldownGenerated) drilldownGenerated.textContent = "Generated: --";
      if (drilldownBody) drilldownBody.textContent = "Loading...";
      if (drilldownWarning) drilldownWarning.classList.add("hidden");
      if (drilldownCopyPorts) drilldownCopyPorts.classList.add("hidden");
      if (drilldownCopyIps) drilldownCopyIps.classList.add("hidden");
      if (drilldownPrev) drilldownPrev.disabled = true;
      if (drilldownNext) drilldownNext.disabled = true;
      if (drilldownPageEl) drilldownPageEl.textContent = "Page 1";
      drilldownOverlay.classList.remove("hidden");

      loadDrilldownPage(1);
    }

    function loadDrilldownPage(page) {
      if (!drilldownState.kind) return;
      drilldownState.page = page;
      const params = new URLSearchParams();
      params.set("window", drilldownState.window);
      params.set("page", drilldownState.page);
      if (drilldownState.options.deviceId) params.set("device_id", drilldownState.options.deviceId);

      fetch(`/drilldowns/${drilldownState.kind}.json?${params.toString()}`)
        .then((resp) => resp.json())
        .then((data) => {
          if (drilldownGenerated && data.generated_at) {
            drilldownGenerated.textContent = `Generated: ${data.generated_at}`;
          }
          const rows = (data.rows || []).filter((row) => {
            if (drilldownState.options.port && row.dst_port != null) {
              return String(row.dst_port) === String(drilldownState.options.port);
            }
            return true;
          });
          if (drilldownWarning) {
            if (data.limited) drilldownWarning.classList.remove("hidden");
            else drilldownWarning.classList.add("hidden");
          }
          drilldownState.totalPages = data.total_pages || 1;
          if (drilldownPageEl) {
            drilldownPageEl.textContent = `Page ${data.page || 1} of ${drilldownState.totalPages}`;
          }
          if (drilldownPrev) drilldownPrev.disabled = (data.page || 1) <= 1;
          if (drilldownNext) drilldownNext.disabled = (data.page || 1) >= drilldownState.totalPages;

          const ports = rows.map((row) => row.dst_port).filter((p) => p != null);
          const ips = rows.map((row) => row.dst_ip).filter((ip) => ip);
          if (drilldownCopyPorts) {
            if (ports.length > 0) drilldownCopyPorts.classList.remove("hidden");
            else drilldownCopyPorts.classList.add("hidden");
            drilldownCopyPorts.onclick = () => {
              navigator.clipboard?.writeText([...new Set(ports)].join("\n"));
            };
          }
          if (drilldownCopyIps) {
            if (ips.length > 0) drilldownCopyIps.classList.remove("hidden");
            else drilldownCopyIps.classList.add("hidden");
            drilldownCopyIps.onclick = () => {
              navigator.clipboard?.writeText([...new Set(ips)].join("\n"));
            };
          }

          drilldownBody.replaceChildren(...(rows.length
            ? rows.map((row) => renderDrilldownRow(row, formatBytes, drilldownState.kind))
            : [el("div", { class: "text-sm text-zinc-200" }, "No results.")]));
        })
        .catch(() => {
          if (drilldownBody) drilldownBody.textContent = "Failed to load drilldown.";
        });
    }

    if (drilldownClose) {
      listen(drilldownClose, "click", closeDrilldown);
    }
    if (drilldownPrev) {
      listen(drilldownPrev, "click", () => {
        if (drilldownState.page > 1) loadDrilldownPage(drilldownState.page - 1);
      });
    }
    if (drilldownNext) {
      listen(drilldownNext, "click", () => {
        if (drilldownState.page < drilldownState.totalPages) loadDrilldownPage(drilldownState.page + 1);
      });
    }
    if (drilldownOverlay) {
      listen(drilldownOverlay, "click", (event) => {
        if (event.target && event.target.classList.contains("drilldown-backdrop")) closeDrilldown();
      });
    }
    listen(document, "keydown", (event) => {
      if (event.key === "Escape") {
        closeDrilldown();
        closeChartModal();
      }
    });

    function closeChartModal() {
      if (chartModal) chartModal.classList.add("hidden");
    }

    function openChartModal(title, points, color, windowLabel) {
      if (!chartModal || !chartModalCanvas) return;
      chartModalTitle.textContent = `${title} (${windowLabel || "10m"})`;
      chartModal.classList.remove("hidden");
      requestAnimationFrame(() => {
        drawLineWithScale(chartModalCanvas, points, color || "#22d3ee");
      });
    }

    if (chartModalClose) {
      listen(chartModalClose, "click", closeChartModal);
    }
    if (chartModal) {
      listen(chartModal, "click", (event) => {
        if (event.target && event.target.classList.contains("chart-backdrop")) closeChartModal();
      });
    }

    const graphs = {
      newDst: { canvas: document.getElementById("graph-new-dst"), color: "#22d3ee" },
      uniqueDports: { canvas: document.getElementById("graph-unique-dports"), color: "#38bdf8" },
      uplinkBytes: { canvas: document.getElementById("graph-uplink-bytes"), color: "#34d399" },
      newAsns: { canvas: document.getElementById("graph-new-asns"), color: "#5eead4" }
    };

    const graphSeriesState = {};

    function drawLineWithScale(canvas, points, color) {
      if (!canvas) return;
      const ctx = canvas.getContext("2d");
      const width = canvas.width = canvas.clientWidth;
      const height = canvas.height = canvas.clientHeight;
      ctx.clearRect(0, 0, width, height);

      if (!points || points.length === 0) {
        ctx.fillStyle = "#71717a";
        ctx.font = "12px sans-serif";
        ctx.fillText("No data yet", 10, 20);
        return;
      }

      const min = Math.min(...points);
      const max = Math.max(...points);
      const range = max - min || 1;

      const leftPad = 28;
      const rightPad = 6;
      const topPad = 6;
      const bottomPad = 12;
      const plotWidth = width - leftPad - rightPad;
      const plotHeight = height - topPad - bottomPad;

      ctx.strokeStyle = "#3f3f46";
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(leftPad, topPad);
      ctx.lineTo(leftPad, topPad + plotHeight);
      ctx.lineTo(leftPad + plotWidth, topPad + plotHeight);
      ctx.stroke();

      ctx.fillStyle = "#71717a";
      ctx.font = "10px sans-serif";
      ctx.fillText(String(max), 2, topPad + 8);
      ctx.fillText(String(min), 2, topPad + plotHeight);

      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.beginPath();
      points.forEach((val, idx) => {
        const x = leftPad + (idx / (points.length - 1 || 1)) * plotWidth;
        const y = topPad + plotHeight - ((val - min) / range) * plotHeight;
        if (idx === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      });
      ctx.stroke();
    }

    function renderMetrics(payload) {
      if (metricsUpdatedEl && payload.timestamp) {
        metricsUpdatedEl.textContent = payload.timestamp;
      }
      if (loadavgEl && payload.loadavg) {
        const { one, five, fifteen } = payload.loadavg;
        loadavgEl.textContent = `${one ?? "--"} / ${five ?? "--"} / ${fifteen ?? "--"}`;
      }
      if (collectorEl) {
        const age = payload.collector?.age_seconds;
        const stale = payload.collector?.stale ?? (age != null ? age > 10 : null);
        collectorIsStale = stale === true;
        if (age == null) {
          collectorEl.textContent = "Unknown";
          collectorEl.className = "text-zinc-200";
        } else {
          const statusClass = stale ? "text-red-300" : "text-emerald-300";
          const label = stale ? "Stale" : "OK";
          collectorEl.textContent = `${label} (${age}s ago)`;
          collectorEl.className = statusClass;
        }
        if (collectorWarningEl) {
          collectorWarningEl.classList.toggle("hidden", !collectorIsStale);
        }
      }
      if (memEl && payload.meminfo) {
        const total = payload.meminfo.total_kb || 0;
        const avail = payload.meminfo.available_kb || 0;
        const used = total - avail;
        memEl.textContent = `${used}k / ${total}k`;
      }
      if (ifacesEl) {
        const lines = (payload.interfaces || []).map((iface) => {
          return `${iface.name}: rx ${formatBytes(iface.rx_bytes ?? 0)}, tx ${formatBytes(iface.tx_bytes ?? 0)}`;
        });
        ifacesEl.textContent = lines.length > 0 ? lines.join(" | ") : "--";
      }

      if (payload.analytics) {
        lastAnalytics = payload.analytics;
        // Stat cards are updated via series fetches to respect per-card windows.
        if (anomaliesEl) {
          const list = (payload.analytics.anomalies || []).map((a) => a.rule);
          const asns = payload.analytics.new_asns_list || [];
          const extra = asns.length > 0 ? ` | ASNs: ${asns.join(", ")}` : "";
          anomaliesEl.textContent = list.length > 0 ? `${list.join("; ")}${extra}` : "None";
        }
      }

      // Graphs are updated via /metrics/series to respect per-graph time windows.
    }

    if (newDstEl) {
      listen(newDstEl, "click", () => {
        const window = document.querySelector(".stat-window[data-series='new_dst_ips_last_10m']")?.value || "10m";
        openDrilldown("new_dst", window, "New DST IPs");
      });
    }

    if (uniqueDportsEl) {
      listen(uniqueDportsEl, "click", () => {
        const window = document.querySelector(".stat-window[data-series='unique_dports_last_10m']")?.value || "10m";
        openDrilldown("unique_ports", window, "Unique DPorts");
      });
    }

    if (newAsnsEl) {
      listen(newAsnsEl, "click", () => {
        const window = document.querySelector(".stat-window[data-series='new_asns_last_1h']")?.value || "1h";
        openDrilldown("new_asns", window, "New ASNs");
      });
    }

    if (rarePortsList) {
      listen(rarePortsList, "click", (event) => {
        const target = event.target;
        if (!target || !target.classList.contains("rare-port-item")) return;
        const port = target.dataset.port;
        const window = document.querySelector(".panel-window[data-panel='rare']")?.value || "24h";
        if (port === "all") {
          openDrilldown("rare_ports", window, "Rare Ports");
        } else {
          openDrilldown("rare_ports", window, `Rare Port ${port}`, { port: port });
        }
      });
    }

    function refreshMetrics(force = false) {
      if (!shouldPoll(force)) return;
      if (inFlightMetrics) return;
      inFlightMetrics = true;
      const controller = beginPollRequest("metrics");
      const interfaces = interfacesInput ? interfacesInput.value.trim() : "";
      const query = interfaces ? `?interfaces=${encodeURIComponent(interfaces)}` : "";
      fetch(`/metrics.json${query}`, { signal: controller.signal })
        .then((resp) => resp.json())
        .then(renderMetrics)
        .catch((error) => {
          if (error?.name !== "AbortError") {
            // no-op: transient poll failures should not disrupt UI
          }
        })
        .finally(() => {
          inFlightMetrics = false;
          endPollRequest("metrics", controller);
        });
    }

    refreshMetrics(true);
    const metricsPollTimer = setInterval(() => refreshMetrics(), 3000);

    if (interfacesInput) {
      let metricsTimer = null;
      listen(interfacesInput, "input", () => {
        clearTimeout(metricsTimer);
        metricsTimer = setTimeout(() => refreshMetrics(true), 200);
      });
    }

    function updateStatCard(seriesKey, window, el, formatter, signal = null) {
      if (!el) return Promise.resolve();
      return fetchSeries(window, signal).then((series) => {
        const points = series[seriesKey] || [];
        const last = points.length > 0 ? points[points.length - 1] : 0;
        const value = formatter ? formatter(last) : last;
        el.textContent = value;
        el.title = last;
      });
    }

    const windowStorageKey = "netmon.graph.windows";

    function loadWindowSelections() {
      let stored = {};
      try {
        stored = JSON.parse(localStorage.getItem(windowStorageKey) || "{}");
      } catch (e) {
        stored = {};
      }
      document.querySelectorAll(".graph-window").forEach((select) => {
        const key = `graph:${select.dataset.series}`;
        if (stored[key]) select.value = stored[key];
      });
      document.querySelectorAll(".system-window").forEach((select) => {
        const key = `system:${select.dataset.metric}`;
        if (stored[key]) select.value = stored[key];
      });
      document.querySelectorAll(".stat-window").forEach((select) => {
        const key = `stat:${select.dataset.series}`;
        if (stored[key]) select.value = stored[key];
      });
    }

    function persistWindowSelection(kind, key, value) {
      let stored = {};
      try {
        stored = JSON.parse(localStorage.getItem(windowStorageKey) || "{}");
      } catch (e) {
        stored = {};
      }
      stored[`${kind}:${key}`] = value;
      localStorage.setItem(windowStorageKey, JSON.stringify(stored));
    }

    loadWindowSelections();

    function refreshStatSeries(force = false) {
      if (!shouldPoll(force)) return;
      if (inFlightStatSeries) return;
      inFlightStatSeries = true;
      const controller = beginPollRequest("stat_series");
      const tasks = [];
      document.querySelectorAll(".stat-window").forEach((select) => {
        const seriesKey = select.dataset.series;
        const window = select.value;
        if (seriesKey === "uplink_bytes_last_10m") {
          tasks.push(updateStatCard(seriesKey, window, uplinkBytesEl, formatBytes, controller.signal));
        } else if (seriesKey === "new_dst_ips_last_10m") {
          tasks.push(updateStatCard(seriesKey, window, newDstEl, null, controller.signal));
        } else if (seriesKey === "unique_dports_last_10m") {
          tasks.push(updateStatCard(seriesKey, window, uniqueDportsEl, null, controller.signal));
        } else if (seriesKey === "new_asns_last_1h") {
          tasks.push(updateStatCard(seriesKey, window, newAsnsEl, null, controller.signal));
        }
      });
      Promise.all(tasks).finally(() => {
        inFlightStatSeries = false;
        endPollRequest("stat_series", controller);
      });
    }

    refreshStatSeries(true);
    const statSeriesPollTimer = setInterval(() => refreshStatSeries(), 15000);

    document.querySelectorAll(".stat-window").forEach((select) => {
      listen(select, "change", () => {
        const seriesKey = select.dataset.series;
        persistWindowSelection("stat", seriesKey, select.value);
        refreshStatSeries(true);
      });
    });

    function refreshGraphSeries(force = false) {
      if (!shouldPoll(force)) return;
      if (inFlightGraphSeries) return;
      inFlightGraphSeries = true;
      const controller = beginPollRequest("graph_series");
      const tasks = [];
      document.querySelectorAll(".graph-window").forEach((select) => {
        const seriesKey = select.dataset.series;
        const window = select.value;
        if (window) persistWindowSelection("graph", seriesKey, window);
        tasks.push(fetchSeries(window, controller.signal).then((series) => {
          const points = series[seriesKey] || [];
          const canvas = document.querySelector(`canvas[data-series="${seriesKey}"]`);
          updateGraph(canvas, seriesKey, points, window);
        }).catch(() => {}));
      });
      Promise.all(tasks).finally(() => {
        inFlightGraphSeries = false;
        endPollRequest("graph_series", controller);
      });
    }

    refreshGraphSeries(true);
    const graphSeriesPollTimer = setInterval(() => refreshGraphSeries(), 15000);


    function seriesKeyFromCanvas(canvas) {
      return canvas?.dataset.series;
    }

    function fetchSeries(window, signal = null) {
      return fetch(`/metrics/series.json?window=${encodeURIComponent(window)}`, { signal })
        .then((resp) => resp.json());
    }

    function updateGraph(canvas, seriesKey, points, windowLabel) {
      const color = Object.values(graphs).find((g) => g.canvas === canvas)?.color || "#36c";
      drawLineWithScale(canvas, points || [], color);
      if (canvas) canvas.dataset.color = color;
      graphSeriesState[seriesKey] = { points: points || [], window: windowLabel };
      if (canvas && windowLabel) {
        const label = document.querySelector(`[data-range-label="${canvas.id}"]`);
        if (label) label.textContent = `Last ${windowLabel}`;
      }
    }

    document.querySelectorAll(".graph-window").forEach((select) => {
      listen(select, "change", () => {
        const window = select.value;
        const seriesKey = select.dataset.series;
        persistWindowSelection("graph", seriesKey, window);
        if (graphSeriesState[seriesKey]) {
          graphSeriesState[seriesKey].window = window;
        } else {
          graphSeriesState[seriesKey] = { points: [], window: window };
        }
        fetchSeries(window).then((series) => {
          const points = series[seriesKey] || [];
          const canvas = document.querySelector(`canvas[data-series="${seriesKey}"]`);
          const color = Object.values(graphs).find((g) => g.canvas === canvas)?.color || "#36c";
          if (canvas) canvas.dataset.color = color;
          updateGraph(canvas, seriesKey, points, window);
        }).catch(() => {});
      });
    });

    listen(window, "popstate", () => refreshGraphSeries(true));

    Object.values(graphs).forEach((graph) => {
      if (!graph.canvas) return;
      listen(graph.canvas, "click", () => {
        const seriesKey = seriesKeyFromCanvas(graph.canvas);
        const state = graphSeriesState[seriesKey];
        if (!state || state.points.length === 0) return;
        const title = seriesKey.replace(/_/g, " ");
        const color = graph.canvas.dataset.color || graph.color;
        openChartModal(title, state.points, color, state.window);
      });
    });

    const systemSeriesState = {};

    function fetchSystemSeries(metric, window, signal = null) {
      return fetch(`/system/series.json?metric=${encodeURIComponent(metric)}&window=${encodeURIComponent(window)}`, { signal })
        .then((resp) => resp.json());
    }

    function updateSystemGraph(canvas, metric, points, windowLabel) {
      const color = "#22d3ee";
      drawLineWithScale(canvas, points || [], color);
      systemSeriesState[metric] = { points: points || [], window: windowLabel };
      if (canvas && windowLabel) {
        const label = document.querySelector(`[data-range-label="${canvas.id}"]`);
        if (label) label.textContent = `Last ${windowLabel}`;
      }
    }

    function refreshSystemGraphs(force = false) {
      if (!shouldPoll(force)) return;
      if (inFlightSystemSeries) return;
      inFlightSystemSeries = true;
      const controller = beginPollRequest("system_series");
      const tasks = [];
      document.querySelectorAll(".system-window").forEach((select) => {
        const metric = select.dataset.metric;
        const window = select.value;
        if (window) persistWindowSelection("system", metric, window);
        tasks.push(fetchSystemSeries(metric, window, controller.signal).then((series) => {
          const points = series.values || [];
          const canvas = document.querySelector(`canvas[data-metric="${metric}"]`);
          updateSystemGraph(canvas, metric, points, window);
        }).catch(() => {}));
      });
      Promise.all(tasks).finally(() => {
        inFlightSystemSeries = false;
        endPollRequest("system_series", controller);
      });
    }

    refreshSystemGraphs(true);
    const systemSeriesPollTimer = setInterval(() => refreshSystemGraphs(), 15000);

    document.querySelectorAll(".system-window").forEach((select) => {
      listen(select, "change", () => {
        const metric = select.dataset.metric;
        persistWindowSelection("system", metric, select.value);
        refreshSystemGraphs(true);
      });
    });

    document.querySelectorAll("canvas[data-metric]").forEach((canvas) => {
      listen(canvas, "click", () => {
        const metric = canvas.dataset.metric;
        const state = systemSeriesState[metric];
        if (!state || state.points.length === 0) return;
        const title = metric.replace(/_/g, " ");
        openChartModal(title, state.points, "#22d3ee", state.window);
      });
    });

    const columnStorageKey = "netmon.columns.connections";
    const columnsConfig = [
      { key: "proto", label: "Proto" },
      { key: "device", label: "Device" },
      { key: "source", label: "Source" },
      { key: "destination", label: "Destination" },
      { key: "domain", label: "Domain" },
      { key: "state", label: "State" },
      { key: "flags", label: "Flags" },
      { key: "up", label: "Up" },
      { key: "down", label: "Down" },
      { key: "total", label: "Total" },
      { key: "score", label: "Score" },
      { key: "reasons", label: "Reasons" },
      { key: "allow", label: "Allow" },
      { key: "age", label: "Age" },
      { key: "rdns", label: "rDNS" },
      { key: "whois", label: "WHOIS" },
      { key: "seen", label: "Seen" }
    ];
    const defaultColumns = ["proto", "device", "destination", "domain", "state", "flags", "up", "down", "total", "score", "reasons", "rdns", "whois"];
    let enabledColumns = [];

    function loadColumnPreferences() {
      try {
        const stored = JSON.parse(localStorage.getItem(columnStorageKey) || "null");
        if (Array.isArray(stored) && stored.length > 0) {
          enabledColumns = stored;
          return;
        }
      } catch (e) {}
      enabledColumns = defaultColumns.slice();
      localStorage.setItem(columnStorageKey, JSON.stringify(enabledColumns));
    }

    function applyColumnVisibility() {
      const enabled = new Set(enabledColumns);
      document.querySelectorAll("[data-col]").forEach((el) => {
        const key = el.dataset.col;
        if (!key) return;
        if (enabled.has(key)) el.classList.remove("hidden");
        else el.classList.add("hidden");
      });
    }

    function renderColumnToggles() {
      const container = document.getElementById("columns-toggle");
      if (!container) return;
      container.replaceChildren(...columnsConfig.map((col) =>
        el("label", { class: "flex items-center gap-2" },
          el("input", { type: "checkbox", class: "rounded border-zinc-700 bg-black text-cyan-400", "data-column": col.key, checked: enabledColumns.includes(col.key) }),
          el("span", {}, col.label))));

      container.querySelectorAll("input[type='checkbox']").forEach((checkbox) => {
        listen(checkbox, "change", () => {
          const key = checkbox.dataset.column;
          if (!key) return;
          if (checkbox.checked) {
            if (!enabledColumns.includes(key)) enabledColumns.push(key);
          } else {
            enabledColumns = enabledColumns.filter((col) => col !== key);
          }
          localStorage.setItem(columnStorageKey, JSON.stringify(enabledColumns));
          applyColumnVisibility();
        });
      });
    }

    loadColumnPreferences();
    renderColumnToggles();
    applyColumnVisibility();

    const topRemoteHostsEl = document.getElementById("panel-top-remote-hosts");
    const newestRemoteHostsEl = document.getElementById("panel-newest-remote-hosts");
    const newestViewAllEl = document.getElementById("panel-newest-viewall");
    const rarePortsEl = document.getElementById("panel-rare-ports");
    const topDevicesEgressEl = document.getElementById("panel-top-devices-egress");
    const recentIncidentsEl = document.getElementById("panel-recent-incidents");


    function refreshTopPanels(force = false) {
      if (!shouldPoll(force)) return;
      if (inFlightTopPanels) return;
      inFlightTopPanels = true;
      const controller = beginPollRequest("top_panels");
      const panelParams = new URLSearchParams();
      let newestWindow = "10m";
      document.querySelectorAll(".panel-window").forEach((select) => {
        const panel = select.dataset.panel;
        if (panel === "top-remote") panelParams.set("top_remote_window", select.value);
        if (panel === "newest") {
          panelParams.set("newest_window", select.value);
          newestWindow = select.value;
        }
        if (panel === "rare") panelParams.set("rare_window", select.value);
        if (panel === "devices-egress") panelParams.set("top_devices_window", select.value);
      });
      const query = panelParams.toString();
      const url = query ? `/dashboard/top_panels.json?${query}` : "/dashboard/top_panels.json";
      fetch(url, { signal: controller.signal })
        .then((resp) => resp.json())
        .then((data) => {
          const topRemote = (data.top_remote_hosts || []).map((row) =>
            el("span", {}, hostLink(row.ip), " (", el("span", { title: row.total_bytes }, formatBytes(row.total_bytes)), ")"));
          const newest = (data.newest_remote_hosts || []).map((row) =>
            hostLink(row.ip, String(row.ip) + (row.port ? ":" + row.port : "")));
          const topDevices = (data.top_devices_egress || []).map((row) =>
            el("span", {}, row.label, " (", el("span", { title: row.total_uplink }, formatBytes(row.total_uplink)), ")"));
          renderPanelList(topRemoteHostsEl, topRemote);
          renderPanelList(newestRemoteHostsEl, newest);
          newestViewAllEl?.setAttribute("href", "/remote_hosts?window=" + encodeURIComponent(newestWindow));
          renderPanelList(topDevicesEgressEl, topDevices);
          if (rarePortsEl) {
            const button = (port, label) => el("button", { type: "button", class: "rare-port-item text-cyan-200 hover:text-cyan-100 rounded", "data-port": port }, label);
            const rows = (data.rare_ports || []).filter((row) => row && row.port != null);
            renderPanelList(rarePortsEl, [button("all", "View All"), ...rows.map((row) => {
              const ips = (row.ips || []).slice(0, 2).join(", ");
              return button(row.port, String(row.port) + " (" + row.count + ")" + (ips ? " — " + ips : ""));
            })]);
          }
          const incidents = (data.recent_incidents || []).map((incident) => {
            const dst = incident.dst_ip ? String(incident.dst_ip) + (incident.dst_port ? ":" + incident.dst_port : "") : "device-level";
            const label = (incident.device || "") + " " + dst + " (" + incident.max_score + ")" + (incident.codes ? " " + incident.codes : "") + (incident.count ? " x" + incident.count : "");
            return el("a", { href: "/incidents/" + encodeURIComponent(String(incident.id)) }, label);
          });
          renderPanelList(recentIncidentsEl, incidents);
        })
        .catch((error) => {
          if (error?.name !== "AbortError") {
            // no-op: transient poll failures should not disrupt UI
          }
        })
        .finally(() => {
          inFlightTopPanels = false;
          endPollRequest("top_panels", controller);
        });
    }

    refreshTopPanels(true);
    const topPanelsPollTimer = setInterval(() => refreshTopPanels(), 15000);

    document.querySelectorAll(".panel-window").forEach((select) => {
      listen(select, "change", () => refreshTopPanels(true));
    });

    listen(document, "visibilitychange", () => {
      if (document.hidden) return;
      refresh(true);
      refreshMetrics(true);
      refreshStatSeries(true);
      refreshGraphSeries(true);
      refreshSystemGraphs(true);
      refreshTopPanels(true);
    });

    disposeDashboard = () => {
      listeners.abort();
      clearTimeout(pendingSave);
      clearInterval(connectionsPollTimer);
      clearInterval(metricsPollTimer);
      clearInterval(statSeriesPollTimer);
      clearInterval(graphSeriesPollTimer);
      clearInterval(systemSeriesPollTimer);
      clearInterval(topPanelsPollTimer);
      abortAllPollRequests();
    };
    listen(window, "pagehide", disposeDashboard);
    listen(document, "turbo:before-cache", disposeDashboard);
  
}
