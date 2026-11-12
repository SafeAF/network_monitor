// Children are always text or DOM nodes. Never interpret telemetry as markup.
export function element(tag, attributes = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attributes)) {
    if (value == null) continue;
    if (key === "value" || key === "checked") node[key] = value;
    else node.setAttribute(key, String(value));
  }
  for (const child of children.flat(Infinity)) {
    if (child != null) node.append(child);
  }
  return node;
}

export function hostLink(ip, label = ip, attributes = {}) {
  return element("a", { ...attributes, href: `/remote_hosts/${encodeURIComponent(String(ip))}` }, label);
}

export function renderPanelList(container, items) {
  container?.replaceChildren(...items.map((item) => element("li", {}, item)));
}
