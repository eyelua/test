"""
Dark Crown — делает иконки и картинки интерфейса из logo.png и упаковывает расширение Crown Tools.

  1. Положи логотип как logo.png рядом (PNG с прозрачным фоном).
  2. pip install pillow
  3. python build-assets.py

Результат: icon.ico, icons/, branding/logo-tile.png, crown-tools/logo.png, crown-tools/icons/,
           logo.css, userContent.css, crowntools.xpi
"""
import base64, io, os, sys, zipfile
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO = os.path.join(HERE, "logo.png")
BG = (14, 14, 18, 255)
SIZES = [16, 32, 48, 64, 128, 256]


def make_tile(logo, size):
    tile = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle([0, 0, size - 1, size - 1], radius=size // 5, fill=BG)
    inner = int(size * 0.82)
    fitted = logo.copy()
    fitted.thumbnail((inner, inner), Image.LANCZOS)
    tile.alpha_composite(fitted, ((size - fitted.width) // 2, (size - fitted.height) // 2))
    return tile


def data_uri(img):
    buf = io.BytesIO()
    img.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


USER_CONTENT = """@import url("accent.css");

/* Dark Crown: полностью чёрное оформление встроенных страниц (настройки, о программе, новая вкладка) */
@-moz-document url-prefix("about:") {
  :root {
    /* Прежние переменные Firefox */
    --in-content-page-background: #000000 !important;
    --in-content-page-color: #e8e6e3 !important;
    --in-content-text-color: #e8e6e3 !important;
    --in-content-box-background: #0a0a0a !important;
    --in-content-box-background-hover: #141414 !important;
    --in-content-box-border-color: #1f1f1f !important;
    --in-content-border-color: #1f1f1f !important;
    --in-content-item-hover: #141414 !important;
    --in-content-item-selected: var(--dc-accent, #d4af37) !important;
    --in-content-accent-color: var(--dc-accent, #d4af37) !important;
    --in-content-primary-button-background: var(--dc-accent, #d4af37) !important;
    --in-content-primary-button-background-hover: var(--dc-accent, #d4af37) !important;
    --in-content-primary-button-background-active: var(--dc-accent, #d4af37) !important;
    --in-content-primary-button-text-color: #000000 !important;
    --in-content-primary-button-text-color-hover: #000000 !important;
    --in-content-primary-button-text-color-active: #000000 !important;

    /* Новые переменные дизайн-системы Firefox */
    --background-color-canvas: #000000 !important;
    --background-color-box: #0a0a0a !important;
    --background-color-box-info: #0a0a0a !important;
    --background-color-three-dimensional: #141414 !important;
    --background-color-interactive: #141414 !important;
    --background-color-interactive-hover: #1a1a1a !important;
    --background-color-interactive-active: #222222 !important;
    --border-color: #1f1f1f !important;
    --border-color-card: #1f1f1f !important;
    --border-color-interactive: #2a2a2a !important;
    --text-color: #e8e6e3 !important;
    --text-color-deemphasized: #9a9a9a !important;
    --link-color: var(--dc-accent, #d4af37) !important;
    --link-color-hover: var(--dc-accent, #d4af37) !important;
    --link-color-active: var(--dc-accent, #d4af37) !important;
    --color-accent-primary: var(--dc-accent, #d4af37) !important;
    --color-accent-primary-hover: var(--dc-accent, #d4af37) !important;
    --color-accent-primary-active: var(--dc-accent, #d4af37) !important;
    --button-background-color-primary: var(--dc-accent, #d4af37) !important;
    --button-background-color-primary-hover: var(--dc-accent, #d4af37) !important;
    --button-background-color-primary-active: var(--dc-accent, #d4af37) !important;
    --button-text-color-primary: #000000 !important;
    --button-text-color-primary-hover: #000000 !important;
    --button-text-color-primary-active: #000000 !important;
    --focus-outline-color: var(--dc-accent, #d4af37) !important;
    --focus-outline: 2px solid var(--dc-accent, #d4af37) !important;
  }
  html, body { background-color: #000000 !important; color: #e8e6e3 !important; }

  /* Логотип LibreWolf в заголовках страниц меняем на свой */
  img[src*="branding"] {
    content: url("__URI__") !important;
  }
}

/* Логотип на новой вкладке и в приватном окне */
@-moz-document url("about:newtab"), url("about:home"), url("about:privatebrowsing") {
  body { background: #000000 !important; }
  .logo-and-wordmark .logo, .logo {
    background-image: url("__URI__") !important;
    background-size: contain !important;
    background-repeat: no-repeat !important;
    background-position: center !important;
    width: 140px !important;
    height: 140px !important;
  }
  .logo-and-wordmark .wordmark { display: none !important; }
}
"""

LOGO_CSS = """/* Dark Crown: логотип в окне «О браузере» */
@-moz-document url(chrome://browser/content/aboutDialog.xhtml) {
  #leftBox {
    background-image: url("__URI__") !important;
    background-size: 120px auto !important;
    background-repeat: no-repeat !important;
    background-position: center 40% !important;
  }
}
"""


def main():
    if not os.path.exists(LOGO):
        sys.exit("Не найден logo.png.")
    logo = Image.open(LOGO).convert("RGBA")
    if logo.getextrema()[3][0] == 255:
        print("ВНИМАНИЕ: у logo.png нет прозрачности.")

    for sub in ("icons", "branding", os.path.join("crown-tools", "icons")):
        os.makedirs(os.path.join(HERE, sub), exist_ok=True)

    tiles = {s: make_tile(logo, s) for s in SIZES}
    for s, t in tiles.items():
        t.save(os.path.join(HERE, "icons", f"icon-{s}.png"))
    for s in (48, 96):
        make_tile(logo, s).save(os.path.join(HERE, "crown-tools", "icons", f"icon-{s}.png"))
    tiles[256].save(os.path.join(HERE, "icon.ico"), sizes=[(s, s) for s in SIZES])

    # Исходник для замены значков внутри самого браузера (make-installer.ps1 масштабирует под любой размер)
    make_tile(logo, 512).save(os.path.join(HERE, "branding", "logo-tile.png"), optimize=True)

    big = logo.copy()
    big.thumbnail((512, 512), Image.LANCZOS)
    big.save(os.path.join(HERE, "crown-tools", "logo.png"), optimize=True)

    small = logo.copy()
    small.thumbnail((192, 192), Image.LANCZOS)
    uri = data_uri(small)
    with open(os.path.join(HERE, "userContent.css"), "w", encoding="utf-8") as f:
        f.write(USER_CONTENT.replace("__URI__", uri))
    with open(os.path.join(HERE, "logo.css"), "w", encoding="utf-8") as f:
        f.write(LOGO_CSS.replace("__URI__", uri))
    print("Иконки, логотип и CSS готовы.")

    ext_dir = os.path.join(HERE, "crown-tools")
    xpi = os.path.join(HERE, "crowntools.xpi")
    with zipfile.ZipFile(xpi, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _, files in os.walk(ext_dir):
            for fn in files:
                full = os.path.join(root, fn)
                z.write(full, os.path.relpath(full, ext_dir).replace(os.sep, "/"))
    print("Расширение упаковано: crowntools.xpi")


if __name__ == "__main__":
    main()
