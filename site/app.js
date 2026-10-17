// @ts-check
"use strict";

/** @template {Element} T @param {string} selector @returns {T | null} */
function one(selector) {
  return /** @type {T | null} */ (document.querySelector(selector));
}
/** @template {Element} T @param {string} selector @returns {T[]} */
function all(selector) {
  return /** @type {T[]} */ (Array.from(document.querySelectorAll(selector)));
}
/** @type {MediaQueryList} */
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
/** @returns {boolean} */
function motionAllowed() {
  return (
    !reducedMotion.matches && !document.body.classList.contains("motion-paused")
  );
}
let toastTimer = 0;
/** @param {string} message @param {boolean} [persistent] */
function notify(message, persistent = false) {
  const toast = /** @type {HTMLElement | null} */ (one("#toast"));
  if (!toast) return;
  window.clearTimeout(toastTimer);
  toast.textContent = message;
  toast.classList.add("visible");
  if (persistent) {
    const trigger = document.activeElement;
    const dismiss = document.createElement("button");
    dismiss.type = "button";
    dismiss.className = "toast-dismiss";
    dismiss.textContent = "Dismiss";
    dismiss.addEventListener("click", () => {
      toast.classList.remove("visible");
      toast.replaceChildren();
      if (trigger instanceof HTMLElement) trigger.focus();
    });
    toast.append(dismiss);
  } else {
    toastTimer = window.setTimeout(
      () => toast.classList.remove("visible"),
      4200,
    );
  }
}
/** @param {string} text @param {string} success */
async function copyText(text, success) {
  try {
    if (!navigator.clipboard) throw new Error("Clipboard unavailable");
    await navigator.clipboard.writeText(text);
    notify(success);
  } catch {
    notify(`Clipboard unavailable. Copy this text: ${text}`, true);
  }
}

// Navigation is a non-modal disclosure. Its ordinary links retain their native behavior.
const menuToggle = /** @type {HTMLButtonElement | null} */ (
  one(".menu-toggle")
);
const mobileNav = /** @type {HTMLElement | null} */ (one("#mobile-nav"));
/** @param {boolean} open */
function setMenu(open) {
  if (!menuToggle || !mobileNav) return;
  menuToggle.setAttribute("aria-expanded", String(open));
  menuToggle.innerHTML = open
    ? 'Close <span aria-hidden="true">−</span>'
    : 'Menu <span aria-hidden="true">+</span>';
  mobileNav.hidden = !open;
}
menuToggle?.addEventListener("click", () =>
  setMenu(menuToggle.getAttribute("aria-expanded") !== "true"),
);
mobileNav?.addEventListener("click", (event) => {
  if (event.target instanceof Element && event.target.closest("a"))
    setMenu(false);
});
document.addEventListener("keydown", (event) => {
  if (
    event.key === "Escape" &&
    menuToggle?.getAttribute("aria-expanded") === "true"
  ) {
    setMenu(false);
    menuToggle.focus();
  }
});
window.matchMedia("(min-width: 851px)").addEventListener("change", (event) => {
  if (event.matches) setMenu(false);
});

all("[data-motion]").forEach((element) => {
  const button = /** @type {HTMLButtonElement} */ (element);
  const update = () => {
    button.disabled = reducedMotion.matches;
    button.textContent = reducedMotion.matches
      ? "Motion reduced"
      : document.body.classList.contains("motion-paused")
        ? "Play motion"
        : "Pause motion";
    button.setAttribute(
      "aria-pressed",
      String(document.body.classList.contains("motion-paused")),
    );
  };
  button.addEventListener("click", () => {
    document.body.classList.toggle("motion-paused");
    update();
  });
  reducedMotion.addEventListener("change", update);
  update();
});

if ("IntersectionObserver" in window) {
  document.body.classList.add("js-reveal");
  const observer = new IntersectionObserver(
    (entries) => {
      for (const entry of entries)
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          entry.target
            .querySelector(".allocation-chart")
            ?.classList.add("is-animated");
          observer.unobserve(entry.target);
        }
    },
    { threshold: 0.07 },
  );
  all(".reveal").forEach((section) => observer.observe(section));
}

// A blessing is local to this visit. No shared or invented community counter.
const mascot = /** @type {HTMLButtonElement | null} */ (one("#bless-mascot"));
let blessings = 0;
let blessingReset = 0;
/** @param {number | undefined} x @param {number | undefined} y */
function bless(x, y) {
  if (!mascot) return;
  const rect = mascot.getBoundingClientRect();
  const label = one("#blessing-label");
  blessings += 1;
  if (label)
    label.textContent = `${blessings} ${blessings === 1 ? "blessing" : "blessings"} this visit. Plush be with you.`;
  mascot.setAttribute(
    "aria-label",
    `Receive a Musegod blessing. ${blessings} this visit.`,
  );
  mascot.classList.remove("blessed");
  void mascot.offsetWidth;
  mascot.classList.add("blessed");
  window.clearTimeout(blessingReset);
  blessingReset = window.setTimeout(
    () => mascot.classList.remove("blessed"),
    900,
  );
  const rings = mascot.querySelector(".blessing-rings");
  if (rings) {
    rings.replaceChildren();
    if (motionAllowed())
      for (let i = 0; i < 3; i++) {
        const ring = document.createElement("span");
        ring.className = "halo-ripple";
        ring.style.setProperty(
          "--x",
          `${x === undefined ? rect.width / 2 : x - rect.left}px`,
        );
        ring.style.setProperty(
          "--y",
          `${y === undefined ? rect.height / 2 : y - rect.top}px`,
        );
        rings.append(ring);
        window.setTimeout(() => ring.remove(), 1300);
      }
  }
}
mascot?.addEventListener("pointerenter", (event) => {
  if (event.pointerType === "mouse") bless(event.clientX, event.clientY);
});
mascot?.addEventListener("click", (event) =>
  bless(
    event.detail === 0 ? undefined : event.clientX,
    event.detail === 0 ? undefined : event.clientY,
  ),
);

/** @param {number} x @param {number} y */
function confetti(x, y) {
  if (!motionAllowed()) return;
  for (let i = 0; i < 18; i++) {
    const piece = document.createElement("span");
    piece.className = "confetti-piece";
    piece.setAttribute("aria-hidden", "true");
    piece.style.setProperty("--x", `${x}px`);
    piece.style.setProperty("--y", `${y}px`);
    piece.style.setProperty("--dx", `${(Math.random() - 0.5) * 260}px`);
    piece.style.setProperty("--dy", `${-40 - Math.random() * 160}px`);
    piece.style.setProperty("--r", `${Math.random() * 320}deg`);
    document.body.append(piece);
    window.setTimeout(() => piece.remove(), 900);
  }
}
all("[data-buy]").forEach((element) =>
  element.addEventListener("click", (event) => {
    const mouse = /** @type {MouseEvent} */ (event);
    const rect = element.getBoundingClientRect();
    confetti(
      mouse.detail === 0 ? rect.x + rect.width / 2 : mouse.clientX,
      mouse.detail === 0 ? rect.y + 10 : mouse.clientY,
    );
  }),
);
all(".magnetic").forEach((element) => {
  const button = /** @type {HTMLElement} */ (element);
  button.addEventListener("pointermove", (event) => {
    if (!motionAllowed() || event.pointerType !== "mouse") return;
    const rect = button.getBoundingClientRect();
    button.style.transform = `translate(${(event.clientX - rect.x - rect.width / 2) * 0.07}px, ${(event.clientY - rect.y - rect.height / 2) * 0.1}px)`;
  });
  button.addEventListener("pointerleave", () => {
    button.style.transform = "";
  });
});

const buyingSteps = [
  [
    "Bring a wallet.",
    "Use a wallet that supports Robinhood Chain. Connect it on the launchpad, where the swap takes place. This website never connects to your wallet.",
  ],
  [
    "Find the real plush.",
    "Get IMD for the swap and Robinhood Chain ETH for gas. Open the SIMD Launchpad coin page, search $MUSEGOD, and verify the contract address below.",
  ],
  [
    "Review. Swap. Receive.",
    "Swap IMD for MUSEGOD on the coin page. Review the quoted output, slippage and fees first: a fixed 2% token fee applies to buys, plus the separate pool fee.",
  ],
];
all("[data-step]").forEach((element) =>
  element.addEventListener("click", () => {
    const button = /** @type {HTMLButtonElement} */ (element);
    const step = buyingSteps[Number(button.dataset.step)];
    if (!step) return;
    all("[data-step]").forEach((other) =>
      other.setAttribute("aria-expanded", String(other === button)),
    );
    const title = one("#step-title"),
      text = one("#step-text");
    if (title) title.textContent = step[0];
    if (text) text.textContent = step[1];
  }),
);

// Bounded pointer drag and a keyboard equivalent. No persistent position or collection.
const sticker = /** @type {HTMLButtonElement | null} */ (one("#plush-sticker"));
if (sticker) {
  let x = 0,
    y = 0,
    startX = 0,
    startY = 0,
    dragging = false;
  const move = () => {
    const zone = sticker.parentElement;
    if (!zone) return;
    const current = sticker.getBoundingClientRect(),
      bounds = zone.getBoundingClientRect();
    const originalLeft = current.left - x,
      originalTop = current.top - y;
    x = Math.min(
      bounds.right - originalLeft - current.width - 8,
      Math.max(bounds.left - originalLeft + 8, x),
    );
    y = Math.min(
      bounds.bottom - originalTop - current.height - 8,
      Math.max(bounds.top - originalTop + 8, y),
    );
    sticker.style.transform = `translate(${x}px, ${y}px)`;
  };
  sticker.addEventListener("pointerdown", (event) => {
    dragging = true;
    startX = event.clientX - x;
    startY = event.clientY - y;
    sticker.setPointerCapture(event.pointerId);
  });
  sticker.addEventListener("pointermove", (event) => {
    if (dragging) {
      x = event.clientX - startX;
      y = event.clientY - startY;
      move();
    }
  });
  const endDrag = () => {
    dragging = false;
  };
  sticker.addEventListener("pointerup", endDrag);
  sticker.addEventListener("pointercancel", endDrag);
  sticker.addEventListener("keydown", (event) => {
    if (
      !["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Home"].includes(
        event.key,
      )
    )
      return;
    event.preventDefault();
    if (event.key === "Home") x = y = 0;
    if (event.key === "ArrowLeft") x -= 12;
    if (event.key === "ArrowRight") x += 12;
    if (event.key === "ArrowUp") y -= 12;
    if (event.key === "ArrowDown") y += 12;
    move();
  });
  window.addEventListener("resize", () => {
    x = y = 0;
    sticker.style.transform = "";
  });
}

// FAQ search is entirely local; nothing typed is submitted anywhere.
const faqSearch = /** @type {HTMLInputElement | null} */ (
  one("[data-faq-search]")
);
faqSearch?.addEventListener("input", () => {
  const query = faqSearch.value.toLowerCase().trim();
  let count = 0;
  all(".faq-item").forEach((element) => {
    const item = /** @type {HTMLDetailsElement} */ (element);
    item.hidden = !(item.textContent || "").toLowerCase().includes(query);
    if (!item.hidden) count += 1;
    if (item.hidden) item.open = false;
  });
  const empty = /** @type {HTMLElement | null} */ (one("[data-search-empty]"));
  if (empty) empty.hidden = count !== 0;
  const status = one("[data-search-count]");
  if (status)
    status.textContent = `${count} ${count === 1 ? "question" : "questions"} found.`;
});

const docsIndex = [
  {
    title: "Overview",
    slug: "",
    text: "musegod mascot robinhood chain brand swarm meme website",
  },
  {
    title: "How it works",
    slug: "how-it-works/",
    text: "buy swap wallet gas eth imd connect launchpad slippage",
  },
  {
    title: "Tokenomics",
    slug: "tokenomics/",
    text: "supply billion 90 pool 10 builders merkle fees fee taxes treasury mint burn 2%",
  },
  {
    title: "Contracts",
    slug: "contracts/",
    text: "contract address poolmanager treasury supply erc20 admin owner totalFeesCollected decimals rules",
  },
  {
    title: "FAQ",
    slug: "faq/",
    text: "questions answers launch fees wallet data memes downloads",
  },
];
const docSearch = /** @type {HTMLInputElement | null} */ (
  one("[data-doc-search]")
);
docSearch?.addEventListener("input", () => {
  const results = /** @type {HTMLElement | null} */ (one("[data-doc-results]"));
  const status = one("[data-doc-count]");
  if (!results || !status) return;
  results.replaceChildren();
  const query = docSearch.value.trim().toLowerCase();
  results.hidden = !query;
  status.textContent = "";
  if (!query) return;
  const root = /** @type {HTMLAnchorElement | null} */ (
    one(".docs-sidebar nav a")
  );
  if (!root) return;
  const matches = docsIndex.filter((item) =>
    `${item.title} ${item.text}`.toLowerCase().includes(query),
  );
  for (const item of matches) {
    const link = document.createElement("a");
    link.href = new URL(item.slug || "./", root.href).href;
    link.textContent = item.title;
    results.append(link);
  }
  status.textContent = matches.length
    ? `${matches.length} ${matches.length === 1 ? "page" : "pages"} found.`
    : "No pages match. Try supply, fees or wallet.";
});

all("[data-copy-link]").forEach((element) =>
  element.addEventListener("click", () =>
    copyText("https://musegod.si-md.xyz/", "Musegod link copied."),
  ),
);

/** @typedef {{marketCap?: unknown, priceUsd?: unknown, volume24h?: unknown}} Market */
/** @typedef {{token?: unknown, coinUrl?: unknown, chartUrl?: unknown, logo?: unknown, market?: Market, status?: unknown}} CoinData */
let contractAddress = "";
/** @param {unknown} value @returns {string} */
function safeUrl(value) {
  if (typeof value !== "string" || !value.trim()) return "";
  try {
    const url = new URL(value, window.location.origin);
    return ["https:", "http:"].includes(url.protocol) &&
      !url.username &&
      !url.password
      ? url.href
      : "";
  } catch {
    return "";
  }
}
/** @param {unknown} value @returns {number | null} */
function numeric(value) {
  if (typeof value !== "number" && (typeof value !== "string" || !value.trim()))
    return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}
const animationValues = new Map();
/** @param {HTMLElement} element @param {number} value @param {string} key */
function animateStat(element, value, key) {
  const previous = animationValues.get(key);
  const start = performance.now();
  const format = (/** @type {number} */ amount) =>
    new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
      maximumFractionDigits:
        key === "priceUsd" ? (amount > 0 && amount < 0.000001 ? 12 : 8) : 0,
      minimumFractionDigits: key === "priceUsd" ? 2 : 0,
      notation: key !== "priceUsd" && amount >= 1e6 ? "compact" : "standard",
    }).format(amount);
  animationValues.set(key, value);
  if (!motionAllowed() || previous === undefined || previous === value) {
    element.textContent = format(value);
    return;
  }
  const frame = (/** @type {number} */ now) => {
    const progress = Math.min(1, (now - start) / 650);
    element.textContent = format(
      previous + (value - previous) * (1 - (1 - progress) ** 3),
    );
    if (progress < 1 && motionAllowed()) requestAnimationFrame(frame);
    else element.textContent = format(value);
  };
  requestAnimationFrame(frame);
}
/** @param {CoinData} data */
function applyCoinData(data) {
  contractAddress =
    typeof data.token === "string" &&
    /^0x[a-fA-F0-9]{40}$/.test(data.token) &&
    !/^0x0{40}$/i.test(data.token)
      ? data.token
      : "";
  all("[data-contract]").forEach((element) => {
    element.textContent = contractAddress || "launching…";
  });
  all("[data-copy-contract]").forEach((element) => {
    /** @type {HTMLButtonElement} */ (element).disabled = !contractAddress;
  });
  const buyUrl = safeUrl(data.coinUrl),
    chartUrl = safeUrl(data.chartUrl);
  all("[data-buy]").forEach((element) => {
    const link = /** @type {HTMLAnchorElement} */ (element);
    link.href = buyUrl || "#buy";
    if (buyUrl) {
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    } else {
      link.removeAttribute("target");
      link.removeAttribute("rel");
    }
  });
  all("[data-chart]").forEach((element) => {
    const link = /** @type {HTMLAnchorElement} */ (element);
    link.hidden = !chartUrl;
    if (chartUrl) {
      link.href = chartUrl;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
    } else link.removeAttribute("href");
  });
  all("[data-launch-note]").forEach((element) => {
    element.textContent = buyUrl
      ? "Swaps open on the coin page."
      : "Trading links appear at launch.";
  });
  const logoUrl = safeUrl(data.logo);
  if (logoUrl)
    all("[data-coin-logo]").forEach((element) => {
      const original = element.getAttribute("href") || "./assets/logo.jpg";
      element.addEventListener(
        "error",
        () => {
          element.setAttribute("href", original);
        },
        { once: true },
      );
      element.setAttribute("href", logoUrl);
    });
  let received = 0;
  const market =
    data.market && typeof data.market === "object" ? data.market : {};
  for (const key of ["priceUsd", "marketCap", "volume24h"]) {
    const value = numeric(market[/** @type {keyof Market} */ (key)]);
    const wrapper = /** @type {HTMLElement | null} */ (
      one(`[data-stat-wrap="${key}"]`)
    );
    const element = /** @type {HTMLElement | null} */ (
      one(`[data-stat="${key}"]`)
    );
    if (wrapper) wrapper.hidden = value === null;
    if (value !== null) {
      received += 1;
      if (element) animateStat(element, value, key);
    }
  }
  const stats = /** @type {HTMLElement | null} */ (one("[data-stats]"));
  if (stats) stats.hidden = received === 0;
  const status = one("[data-data-status]");
  if (status)
    status.textContent = received
      ? `Updated ${new Date().toLocaleTimeString("en-US", { hour: "2-digit", minute: "2-digit" })}. Refreshes every 30s.`
      : contractAddress
        ? "Market data is not available yet."
        : "Awaiting launch data.";
}
all("[data-copy-contract]").forEach((element) =>
  element.addEventListener("click", () => {
    if (contractAddress)
      void copyText(contractAddress, "MUSEGOD contract copied.");
  }),
);
let requestPending = false;
async function refreshCoin() {
  if (requestPending) return;
  requestPending = true;
  all("[data-retry]").forEach((element) => {
    /** @type {HTMLButtonElement} */ (element).disabled = true;
  });
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch("/simd-coin.json", {
      signal: controller.signal,
      cache: "no-store",
      credentials: "omit",
    });
    if (!response.ok) throw new Error("Launch metadata unavailable");
    const data = await response.json();
    if (!data || typeof data !== "object" || Array.isArray(data))
      throw new Error("Invalid launch metadata");
    applyCoinData(data);
  } catch {
    const stats = /** @type {HTMLElement | null} */ (one("[data-stats]"));
    if (stats) stats.hidden = true;
    const status = one("[data-data-status]");
    if (status)
      status.textContent = "Launch data unavailable. Refresh to try again.";
  } finally {
    window.clearTimeout(timeout);
    requestPending = false;
    all("[data-retry]").forEach((element) => {
      /** @type {HTMLButtonElement} */ (element).disabled = false;
    });
  }
}
all("[data-retry]").forEach((element) =>
  element.addEventListener("click", refreshCoin),
);
void refreshCoin();
window.setInterval(() => {
  if (!document.hidden) void refreshCoin();
}, 30000);
document.addEventListener("visibilitychange", () => {
  if (!document.hidden) void refreshCoin();
});
