import { element as el, hostLink } from "./dom.js";

export function renderConnectionRow(conn, formatBytes) {
  const row = el("tr", { class: "odd:bg-black even:bg-zinc-950/30 hover:bg-zinc-900/50" });
  const cell = (column, content, attributes = {}) => {
    const node = el("td", { class: "px-2 py-1.5", "data-col": column, ...attributes }, content);
    row.append(node);
    return node;
  };
  cell("proto", conn.proto);
  cell("device", conn.device_id
    ? el("input", { class: "device-name-input bg-black border border-zinc-800 rounded-lg px-2 py-1 text-zinc-200 text-xs", "data-device-id": conn.device_id, value: conn.device_name || "", size: 12 })
    : conn.device_name || conn.src_ip);
  const source = cell("source", hostLink(conn.src_ip));
  if (conn.src_port) source.append(`:${conn.src_port}`);
  const destination = cell("destination", hostLink(conn.dst_ip));
  if (conn.dst_port) destination.append(`:${conn.dst_port}`);
  const domainTitle = conn.last_domain_observed_at
    ? `${conn.last_domain} (seen ${conn.last_domain_observed_at})` : conn.last_domain || "";
  cell("domain", conn.last_domain
    ? el("a", { href: `/search/hosts?${new URLSearchParams({ domain: conn.last_domain })}`, title: domainTitle }, conn.last_domain)
    : "--", { title: domainTitle, class: "px-2 py-1.5 max-w-[260px] truncate" });
  cell("state", conn.state || "");
  cell("flags", conn.flags || "");
  for (const [column, value] of [["up", conn.uplink_bytes], ["down", conn.downlink_bytes], ["total", conn.total_bytes]]) {
    cell(column, formatBytes(value), { title: value, class: "px-2 py-1.5 text-right" });
  }
  const score = Number(conn.anomaly_score || 0);
  const scoreClass = score >= 70 ? "bg-red-950/30 text-red-200 border-red-800/40"
    : score >= 50 ? "bg-amber-950/30 text-amber-200 border-amber-800/40"
      : score >= 20 ? "bg-cyan-950/30 text-cyan-200 border-cyan-800/40" : "bg-zinc-900/60 text-zinc-200 border-zinc-700";
  cell("score", el("span", { class: `inline-flex px-2 py-0.5 rounded-full text-xs border ${scoreClass}` }, String(score)));
  const reasons = (conn.anomaly_reasons || []).join(",");
  cell("reasons", reasons, { title: reasons, class: "px-2 py-1.5 max-w-[260px] truncate" });
  cell("allow", conn.device_id && conn.dst_port
    ? el("button", { type: "button", class: "allow-port-btn bg-cyan-600/15 text-cyan-200 border border-cyan-700/40 rounded-lg px-2 py-0.5 text-xs", "data-device-id": conn.device_id, "data-port": conn.dst_port }, "Allow port") : "");
  cell("age", conn.seen_age || "unknown");
  cell("rdns", conn.rdns_name || "--", { title: conn.rdns_name || "", class: "px-2 py-1.5 max-w-[260px] truncate" });
  cell("whois", conn.whois_name || "--", { title: conn.whois_raw_line || "", class: "px-2 py-1.5 max-w-[260px] truncate" });
  cell("seen", el("span", { class: "inline-flex px-2 py-0.5 rounded-full text-xs border border-zinc-700 text-cyan-200" }, conn.is_new ? "NEW" : "SEEN"));
  return row;
}

export function renderDrilldownRow(row, formatBytes, fallbackReason) {
  const fields = [
    ["Timestamp", row.timestamp || "--"], ["Device", row.device || "--"],
    ["Proto", row.proto || "--"], ["Dst", row.dst_ip ? hostLink(row.dst_ip, row.dst_ip, { target: "_blank", rel: "noopener" }) : "--"],
    ["Port", String(row.dst_port ?? "--")], ["Bytes", formatBytes(row.bytes)]
  ];
  const result = el("div", { class: "border border-zinc-800/60 rounded-xl p-3 bg-black/60" },
    el("div", { class: "grid grid-cols-2 gap-2 text-sm text-zinc-200" },
      fields.map(([label, value]) => el("div", {}, el("span", { class: "text-xs uppercase tracking-wider text-zinc-500" }, label), el("div", {}, value)))),
    el("div", { class: "mt-2 text-xs text-emerald-200" }, `Why: ${row.reason || fallbackReason}`));
  if (row.count != null) result.append(el("div", { class: "mt-2 text-xs text-zinc-300" },
    `First Seen: ${row.first_seen_at || "--"} · Last Seen: ${row.last_seen_at || "--"} · Count: ${row.count}`));
  if (row.ips?.length) {
    result.append(el("details", { class: "mt-2 text-xs text-zinc-300" },
      el("summary", { class: "text-cyan-200 cursor-pointer" }, `View IPs (${row.ips.length})`),
      row.ips.map((ip) => hostLink(ip, ip, { class: "text-cyan-200 mr-2", target: "_blank", rel: "noopener" }))));
  }
  return result;
}
