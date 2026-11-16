// Crown Tools — встроенные функции Dark Crown Browser

const ALL_DATA = {
  cache: true,
  cookies: true,
  downloads: true,
  formData: true,
  history: true,
  indexedDB: true,
  localStorage: true,
  serviceWorkers: true,
};

const SESSION_DATA = {
  cache: true,
  cookies: true,
  localStorage: true,
  indexedDB: true,
  serviceWorkers: true,
};

function notify(message) {
  browser.notifications.create({
    type: "basic",
    iconUrl: browser.runtime.getURL("icons/icon-96.png"),
    title: "Dark Crown",
    message,
  });
}

// Кнопка паники: стереть всё, закрыть все окна, открыть чистое окно
async function panic() {
  const oldWindows = await browser.windows.getAll();
  await browser.windows.create({ url: "about:blank" });
  await browser.browsingData.remove({ since: 0 }, ALL_DATA);
  for (const w of oldWindows) {
    try {
      await browser.windows.remove(w.id);
    } catch (e) {
      // окно уже закрыто
    }
  }
}

// Быстрая очистка: куки, кэш и хранилище, вкладки остаются
async function quickClean() {
  await browser.browsingData.remove({ since: 0 }, SESSION_DATA);
  notify("Куки, кэш и локальное хранилище очищены.");
}

browser.browserAction.onClicked.addListener(panic);

browser.commands.onCommand.addListener((command) => {
  if (command === "panic") panic();
  if (command === "quick-clean") quickClean();
});

// Сообщения со стартовой страницы (кнопки на ней)
browser.runtime.onMessage.addListener((msg) => {
  if (msg && msg.cmd === "panic") panic();
  if (msg && msg.cmd === "quick-clean") quickClean();
});

// Скрыть все окна (босс-кнопка)
async function bossKey() {
  const wins = await browser.windows.getAll();
  for (const w of wins) {
    try {
      await browser.windows.update(w.id, { state: "minimized" });
    } catch (e) {
      // окно уже закрыто
    }
  }
}

// Автоочистка при бездействии: через 15 минут без активности стираем куки, кэш и хранилище
const IDLE_SECONDS = 15 * 60;
browser.idle.setDetectionInterval(IDLE_SECONDS);
browser.idle.onStateChanged.addListener(async (state) => {
  if (state === "idle" || state === "locked") {
    try {
      await browser.browsingData.remove({ since: 0 }, SESSION_DATA);
    } catch (e) {
      // не страшно, попробуем в следующий раз
    }
  }
});

browser.commands.onCommand.addListener((command) => {
  if (command === "boss-key") bossKey();
});

browser.runtime.onMessage.addListener((msg) => {
  if (msg && msg.cmd === "boss-key") bossKey();
});
