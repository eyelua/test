document.getElementById("panic").addEventListener("click", () => {
  browser.runtime.sendMessage({ cmd: "panic" });
});
document.getElementById("clean").addEventListener("click", () => {
  browser.runtime.sendMessage({ cmd: "quick-clean" });
});
document.getElementById("hide").addEventListener("click", () => {
  browser.runtime.sendMessage({ cmd: "boss-key" });
});
