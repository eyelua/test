package app.darkcrown.browser;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.PopupMenu;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import org.mozilla.geckoview.ContentBlocking;
import org.mozilla.geckoview.GeckoResult;
import org.mozilla.geckoview.GeckoRuntime;
import org.mozilla.geckoview.GeckoRuntimeSettings;
import org.mozilla.geckoview.GeckoSession;
import org.mozilla.geckoview.GeckoSessionSettings;
import org.mozilla.geckoview.GeckoView;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.List;

/**
 * Dark Crown Browser для Android: оболочка на движке Gecko (GeckoView).
 * Всё в приватном режиме: куки, история и кэш не сохраняются на устройстве.
 *
 * Методы делегатов намеренно объявлены без @Override: сигнатуры GeckoView немного
 * меняются между версиями, а так лишний вариант просто не вызывается и не ломает сборку.
 */
public class MainActivity extends Activity {

    private static final String HOME = "resource://android/assets/start.html";
    private static final int DIALOG_THEME = android.R.style.Theme_Material_Dialog_Alert;

    private static GeckoRuntime sRuntime;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private final List<Tab> tabs = new ArrayList<>();
    private Tab current;
    private boolean fullscreen;

    private GeckoView geckoView;
    private EditText urlField;
    private TextView tabsButton;
    private ProgressBar progressBar;
    private View topBar;

    /** Одна вкладка = одна приватная сессия Gecko. */
    static final class Tab {
        final GeckoSession session;
        String url = "";
        String title = "";
        boolean canGoBack;
        int progress = 100;

        Tab(GeckoSession session) {
            this.session = session;
        }
    }

    // ------------------------------------------------------------------ жизненный цикл

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Запрет скриншотов и миниатюры в списке недавних: на экране могут быть токены и пароли
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE);

        setContentView(R.layout.activity_main);
        geckoView = findViewById(R.id.gecko_view);
        urlField = findViewById(R.id.url_field);
        tabsButton = findViewById(R.id.tabs_button);
        progressBar = findViewById(R.id.progress);
        topBar = findViewById(R.id.top_bar);

        ensureRuntime();

        urlField.setOnEditorActionListener((v, actionId, event) -> {
            boolean enter = event != null && event.getKeyCode() == KeyEvent.KEYCODE_ENTER
                    && event.getAction() == KeyEvent.ACTION_DOWN;
            if (actionId == EditorInfo.IME_ACTION_GO || enter) {
                go(urlField.getText().toString());
                hideKeyboard();
                urlField.clearFocus();
                geckoView.requestFocus();
                return true;
            }
            return false;
        });
        urlField.setOnFocusChangeListener((v, hasFocus) -> {
            if (!hasFocus) refreshBar();
        });
        tabsButton.setOnClickListener(v -> showTabs());
        findViewById(R.id.menu_button).setOnClickListener(this::showMenu);

        newTab(startUrlFrom(getIntent()));
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String url = startUrlFrom(intent);
        if (!HOME.equals(url)) newTab(url);
    }

    @Override
    public void onBackPressed() {
        if (fullscreen && current != null) {
            current.session.exitFullScreen();
        } else if (current != null && current.canGoBack) {
            current.session.goBack();
        } else if (tabs.size() > 1) {
            closeTab(current);
        } else {
            moveTaskToBack(true);
        }
    }

    // ------------------------------------------------------------------ Gecko

    private void ensureRuntime() {
        if (sRuntime != null) return;

        ContentBlocking.Settings.Builder cb = new ContentBlocking.Settings.Builder()
                .antiTracking(ContentBlocking.AntiTracking.STRICT)
                .safeBrowsing(ContentBlocking.SafeBrowsing.DEFAULT)
                .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY_AND_ISOLATE_OTHERS)
                .cookieBehaviorPrivateMode(ContentBlocking.CookieBehavior.ACCEPT_FIRST_PARTY_AND_ISOLATE_OTHERS);
        // Необязательные настройки: если в этой версии GeckoView их нет, просто пропускаем
        call(cb, "strictSocialTrackingProtection", boolean.class, true);

        GeckoRuntimeSettings.Builder rs = new GeckoRuntimeSettings.Builder()
                .aboutConfigEnabled(false)
                .remoteDebuggingEnabled(false)
                .consoleOutput(false)
                .contentBlocking(cb.build());
        call(rs, "allowInsecureConnections", int.class, 2);   // 2 = только HTTPS
        call(rs, "preferredColorScheme", int.class, 1);       // 1 = тёмная тема сайтов

        sRuntime = GeckoRuntime.create(getApplicationContext(), rs.build());
    }

    /** Вызывает необязательный метод билдера, если он есть. */
    private static void call(Object target, String method, Class<?> argType, Object arg) {
        try {
            target.getClass().getMethod(method, argType).invoke(target, arg);
        } catch (Throwable ignored) {
            // нет такого метода в этой версии GeckoView
        }
    }

    private Tab createTab() {
        GeckoSessionSettings settings = new GeckoSessionSettings.Builder()
                .usePrivateMode(true)
                .build();
        GeckoSession session = new GeckoSession(settings);
        Tab tab = new Tab(session);
        session.setNavigationDelegate(new Nav(tab));
        session.setProgressDelegate(new Prog(tab));
        session.setContentDelegate(new Content(tab));
        session.setPromptDelegate(new Prompts());
        attachSelectionDelegate(session);
        return tab;
    }

    /** Копирование и вставка текста (меню выделения). Через рефлексию, чтобы не зависеть от версии. */
    private void attachSelectionDelegate(GeckoSession session) {
        try {
            Class<?> c = Class.forName("org.mozilla.geckoview.BasicSelectionActionDelegate");
            Object d = c.getConstructor(Activity.class).newInstance(this);
            session.setSelectionActionDelegate((GeckoSession.SelectionActionDelegate) d);
        } catch (Throwable ignored) {
            // без меню выделения браузер всё равно работает
        }
    }

    private Tab newTab(String url) {
        Tab tab = createTab();
        tab.session.open(sRuntime);
        tabs.add(tab);
        switchTo(tab);
        tab.url = url;
        tab.session.loadUri(url);
        updateTabsButton();
        return tab;
    }

    private void switchTo(Tab tab) {
        current = tab;
        if (!tab.session.isOpen()) tab.session.open(sRuntime);
        geckoView.setSession(tab.session);
        refreshBar();
    }

    private void closeTab(Tab tab) {
        if (tab == null) return;
        int index = tabs.indexOf(tab);
        tabs.remove(tab);
        if (tabs.isEmpty()) {
            tab.session.close();
            newTab(HOME);
            return;
        }
        if (tab == current) {
            switchTo(tabs.get(Math.min(Math.max(index, 0), tabs.size() - 1)));
        }
        tab.session.close();
        updateTabsButton();
    }

    // ------------------------------------------------------------------ адресная строка

    private String startUrlFrom(Intent intent) {
        if (intent != null && Intent.ACTION_VIEW.equals(intent.getAction()) && intent.getData() != null) {
            String s = intent.getData().toString();
            if (s.startsWith("https://") || s.startsWith("http://")) return s;
        }
        return HOME;
    }

    private void go(String input) {
        if (current == null) return;
        String t = input.trim();
        if (t.isEmpty()) return;
        String lower = t.toLowerCase();

        // Опасные схемы вручную не открываем (защита от «вставь это в адресную строку»)
        if (lower.startsWith("javascript:") || lower.startsWith("data:") || lower.startsWith("file:")
                || lower.startsWith("content:") || lower.startsWith("blob:")) {
            Toast.makeText(this, "Этот тип адреса заблокирован", Toast.LENGTH_SHORT).show();
            return;
        }

        String uri;
        if (lower.matches("^[a-z][a-z0-9+.-]*://.*")) {
            uri = t;
        } else if (!t.contains(" ") && t.contains(".")) {
            uri = "https://" + t;
        } else {
            uri = "https://duckduckgo.com/?q=" + Uri.encode(t);
        }
        current.session.loadUri(uri);
    }

    private void refreshBar() {
        if (current == null) return;
        if (!urlField.hasFocus()) {
            urlField.setText(HOME.equals(current.url) ? "" : current.url);
        }
        progressBar.setProgress(current.progress);
        progressBar.setVisibility(current.progress >= 100 ? View.GONE : View.VISIBLE);
    }

    private void updateTabsButton() {
        tabsButton.setText(String.valueOf(tabs.size()));
    }

    private void hideKeyboard() {
        InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
        if (imm != null) imm.hideSoftInputFromWindow(urlField.getWindowToken(), 0);
    }

    // ------------------------------------------------------------------ вкладки и меню

    private String label(Tab t) {
        if (t.title != null && !t.title.isEmpty()) return t.title;
        if (t.url != null && !t.url.isEmpty() && !HOME.equals(t.url)) return t.url;
        return "Новая вкладка";
    }

    private void showTabs() {
        String[] names = new String[tabs.size()];
        for (int i = 0; i < names.length; i++) {
            Tab t = tabs.get(i);
            names[i] = (t == current ? "● " : "") + label(t);
        }
        new AlertDialog.Builder(this, DIALOG_THEME)
                .setTitle("Вкладки: " + tabs.size())
                .setItems(names, (d, which) -> switchTo(tabs.get(which)))
                .setPositiveButton("Новая", (d, w) -> newTab(HOME))
                .setNeutralButton("Закрыть эту", (d, w) -> closeTab(current))
                .setNegativeButton("Назад", null)
                .show();
    }

    private void showMenu(View anchor) {
        PopupMenu menu = new PopupMenu(this, anchor);
        menu.getMenu().add(0, 1, 0, "Назад");
        menu.getMenu().add(0, 2, 1, "Вперёд");
        menu.getMenu().add(0, 3, 2, "Обновить");
        menu.getMenu().add(0, 4, 3, "Новая вкладка");
        menu.getMenu().add(0, 5, 4, "Быстрая очистка");
        menu.getMenu().add(0, 6, 5, "Кнопка паники");
        menu.setOnMenuItemClickListener(item -> {
            if (current == null) return true;
            switch (item.getItemId()) {
                case 1: current.session.goBack(); break;
                case 2: current.session.goForward(); break;
                case 3: current.session.reload(); break;
                case 4: newTab(HOME); break;
                case 5:
                    clearAllData();
                    Toast.makeText(this, "Данные сайтов очищены", Toast.LENGTH_SHORT).show();
                    break;
                case 6: panic(); break;
                default: break;
            }
            return true;
        });
        menu.show();
    }

    // ------------------------------------------------------------------ очистка и паника

    private void clearAllData() {
        try {
            sRuntime.getStorageController().clearData(allClearFlags());
        } catch (Throwable t) {
            Toast.makeText(this, "Не удалось очистить данные", Toast.LENGTH_SHORT).show();
        }
    }

    /** Все флаги очистки (куки, кэш, хранилище сайтов и т.д.). */
    private static long allClearFlags() {
        try {
            Class<?> c = Class.forName("org.mozilla.geckoview.StorageController$ClearFlags");
            try {
                return ((Number) c.getField("ALL").get(null)).longValue();
            } catch (Throwable noAll) {
                long flags = 0;
                for (Field f : c.getFields()) {
                    Object v = f.get(null);
                    if (v instanceof Number) flags |= ((Number) v).longValue();
                }
                return flags;
            }
        } catch (Throwable t) {
            return -1L;
        }
    }

    /** Стереть всё, закрыть все вкладки и полностью завершить процесс (память тоже очищается). */
    private void panic() {
        clearAllData();
        for (Tab t : new ArrayList<>(tabs)) {
            try {
                t.session.close();
            } catch (Throwable ignored) {
                // уже закрыта
            }
        }
        tabs.clear();
        handler.postDelayed(() -> {
            finishAndRemoveTask();
            android.os.Process.killProcess(android.os.Process.myPid());
        }, 700);
    }

    private void setFullscreen(boolean on) {
        fullscreen = on;
        topBar.setVisibility(on ? View.GONE : View.VISIBLE);
        progressBar.setVisibility(View.GONE);
        getWindow().getDecorView().setSystemUiVisibility(on
                ? View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY | View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                : View.SYSTEM_UI_FLAG_VISIBLE);
        if (!on) refreshBar();
    }

    // ------------------------------------------------------------------ делегаты Gecko

    private final class Nav implements GeckoSession.NavigationDelegate {
        private final Tab tab;

        Nav(Tab tab) {
            this.tab = tab;
        }

        private void location(String url) {
            if (url == null) return;
            tab.url = url;
            if (tab == current) refreshBar();
        }

        // Разные версии GeckoView: объявляем все известные варианты
        public void onLocationChange(GeckoSession s, String url, List perms, Boolean userGesture) {
            location(url);
        }

        public void onLocationChange(GeckoSession s, String url, List perms, boolean userGesture) {
            location(url);
        }

        public void onLocationChange(GeckoSession s, String url, List perms) {
            location(url);
        }

        public void onLocationChange(GeckoSession s, String url) {
            location(url);
        }

        public void onCanGoBack(GeckoSession s, boolean canGoBack) {
            tab.canGoBack = canGoBack;
        }

        public void onCanGoForward(GeckoSession s, boolean canGoForward) {
            // не используется
        }

        /** Новые окна (target=_blank, вход через сторонние сервисы) открываем как новую вкладку. */
        public GeckoResult<GeckoSession> onNewSession(GeckoSession s, String uri) {
            final Tab created = createTab();
            tabs.add(created);
            handler.postDelayed(() -> {
                if (tabs.contains(created)) {
                    switchTo(created);
                    updateTabsButton();
                }
            }, 150);
            return GeckoResult.fromValue(created.session);
        }
    }

    private final class Prog implements GeckoSession.ProgressDelegate {
        private final Tab tab;

        Prog(Tab tab) {
            this.tab = tab;
        }

        public void onPageStart(GeckoSession s, String url) {
            tab.progress = 5;
            if (url != null) tab.url = url;
            if (tab == current) refreshBar();
        }

        public void onProgressChange(GeckoSession s, int progress) {
            tab.progress = progress;
            if (tab == current) refreshBar();
        }

        public void onPageStop(GeckoSession s, boolean success) {
            tab.progress = 100;
            if (tab == current) refreshBar();
        }
    }

    private final class Content implements GeckoSession.ContentDelegate {
        private final Tab tab;

        Content(Tab tab) {
            this.tab = tab;
        }

        public void onTitleChange(GeckoSession s, String title) {
            tab.title = title == null ? "" : title;
        }

        public void onCloseRequest(GeckoSession s) {
            closeTab(tab);
        }

        public void onFullScreen(GeckoSession s, boolean fullScreen) {
            setFullscreen(fullScreen);
        }
    }

    /** Окна сайтов: alert, confirm и выпадающие списки (select). */
    private final class Prompts implements GeckoSession.PromptDelegate {

        public GeckoResult<PromptResponse> onAlertPrompt(GeckoSession s, AlertPrompt prompt) {
            final GeckoResult<PromptResponse> result = new GeckoResult<>();
            new AlertDialog.Builder(MainActivity.this, DIALOG_THEME)
                    .setMessage(prompt.message)
                    .setPositiveButton("OK", (d, w) -> result.complete(prompt.dismiss()))
                    .setOnCancelListener(d -> result.complete(prompt.dismiss()))
                    .show();
            return result;
        }

        public GeckoResult<PromptResponse> onButtonPrompt(GeckoSession s, ButtonPrompt prompt) {
            final GeckoResult<PromptResponse> result = new GeckoResult<>();
            new AlertDialog.Builder(MainActivity.this, DIALOG_THEME)
                    .setMessage(prompt.message)
                    .setPositiveButton("OK", (d, w) -> result.complete(prompt.confirm(ButtonPrompt.Type.POSITIVE)))
                    .setNegativeButton("Отмена", (d, w) -> result.complete(prompt.confirm(ButtonPrompt.Type.NEGATIVE)))
                    .setOnCancelListener(d -> result.complete(prompt.dismiss()))
                    .show();
            return result;
        }

        public GeckoResult<PromptResponse> onChoicePrompt(GeckoSession s, ChoicePrompt prompt) {
            final GeckoResult<PromptResponse> result = new GeckoResult<>();
            final ChoicePrompt.Choice[] choices = prompt.choices;
            if (prompt.type == ChoicePrompt.Type.MULTIPLE || choices == null || choices.length == 0) {
                result.complete(prompt.dismiss());
                return result;
            }
            String[] labels = new String[choices.length];
            for (int i = 0; i < choices.length; i++) {
                labels[i] = choices[i].label == null ? "" : choices[i].label;
            }
            new AlertDialog.Builder(MainActivity.this, DIALOG_THEME)
                    .setItems(labels, (d, which) -> result.complete(prompt.confirm(choices[which].id)))
                    .setOnCancelListener(d -> result.complete(prompt.dismiss()))
                    .show();
            return result;
        }
    }
}
