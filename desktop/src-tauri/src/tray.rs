use crate::{formatting, popup, proxy::ProxyClient, updater, widget, window};
use serde_json::Value;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Mutex,
};
use tauri::{
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, PhysicalPosition, Wry,
};
use tauri_plugin_autostart::ManagerExt;
use tauri_plugin_opener::OpenerExt;

pub struct TrayState {
    pub menu: Mutex<Option<UpdateMenu>>,
    pub installing: AtomicBool,
    refresh: tokio::sync::Mutex<()>,
}

pub struct UpdateMenu {
    tray_menu: Menu<Wry>,
    today: MenuItem<Wry>,
    today_visible: bool,
    settings: Value,
    check_updates: MenuItem<Wry>,
    install_update: MenuItem<Wry>,
}

impl Default for TrayState {
    fn default() -> Self {
        Self {
            menu: Mutex::new(None),
            installing: AtomicBool::new(false),
            refresh: tokio::sync::Mutex::new(()),
        }
    }
}

pub fn install(app: &AppHandle, proxy: ProxyClient) -> tauri::Result<()> {
    let today = MenuItem::with_id(app, "today", "Today · Unavailable", false, None::<&str>)?;
    let refresh = MenuItem::with_id(
        app,
        "refresh-now",
        "Refresh now · every 60s",
        true,
        None::<&str>,
    )?;
    let show_usage = MenuItem::with_id(app, "show-usage", "Show Usage", true, None::<&str>)?;
    let open = MenuItem::with_id(app, "open-dashboard", "Open Dashboard", true, None::<&str>)?;
    let browser = MenuItem::with_id(app, "open-browser", "Open in Browser", true, None::<&str>)?;
    let login = CheckMenuItem::with_id(
        app,
        "start-at-login",
        "Start at Login",
        true,
        app.autolaunch().is_enabled().unwrap_or(false),
        None::<&str>,
    )?;
    let spawned_by_us = app
        .state::<crate::AppState>()
        .spawned_by_us
        .load(Ordering::Relaxed);
    let stop = MenuItem::with_id(app, "stop-proxy", "Stop proxy", spawned_by_us, None::<&str>)?;
    let stop_item = stop.clone();
    let check_updates = MenuItem::with_id(
        app,
        "check-updates",
        "Check for Updates…",
        true,
        None::<&str>,
    )?;
    let install_update =
        MenuItem::with_id(app, "install-update", "Install update", false, None::<&str>)?;
    let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
    let menu = Menu::with_items(
        app,
        &[
            &today,
            &refresh,
            &show_usage,
            &open,
            &browser,
            &PredefinedMenuItem::separator(app)?,
            &login,
            &stop,
            &PredefinedMenuItem::separator(app)?,
            &check_updates,
            &install_update,
            &PredefinedMenuItem::separator(app)?,
            &quit,
        ],
    )?;
    if let Ok(mut state) = app.state::<TrayState>().menu.lock() {
        *state = Some(UpdateMenu {
            tray_menu: menu.clone(),
            today: today.clone(),
            today_visible: true,
            settings: Value::Null,
            check_updates: check_updates.clone(),
            install_update: install_update.clone(),
        });
    }

    let tray = TrayIconBuilder::with_id("main")
        .icon(icon())
        .icon_as_template(true)
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_tray_icon_event(|tray, event| {
            #[cfg(any(target_os = "macos", target_os = "windows"))]
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                position,
                ..
            } = event
            {
                let app = tray.app_handle();
                let endpoint = app.state::<crate::AppState>().proxy.endpoint();
                let _ = popup::toggle(&app, endpoint, position);
            }
        })
        .on_menu_event(move |app, event| match event.id().as_ref() {
            "refresh-now" => {
                if let Some(tray) = app.tray_by_id("main") {
                    refresh_title(&tray, &app.state::<crate::AppState>().proxy);
                }
            }
            "show-usage" => {
                let position = app
                    .cursor_position()
                    .unwrap_or_else(|_| PhysicalPosition::new(0.0, 0.0));
                let endpoint = app.state::<crate::AppState>().proxy.endpoint();
                let _ = popup::show(&app, endpoint, position);
            }
            "open-dashboard" => {
                popup::hide(app);
                if let Some(window) = app.get_webview_window("main") {
                    window::show(&window);
                }
            }
            "open-browser" => {
                popup::hide(app);
                let endpoint = app.state::<crate::AppState>().proxy.endpoint();
                let _ = app
                    .opener()
                    .open_url(format!("{}#/usage", endpoint.url("/")), None::<String>);
            }
            "start-at-login" => {
                let enabled = app.autolaunch().is_enabled().unwrap_or(false);
                if enabled {
                    let _ = app.autolaunch().disable();
                } else {
                    let _ = app.autolaunch().enable();
                }
            }
            "stop-proxy" => {
                if app
                    .state::<crate::AppState>()
                    .spawned_by_us
                    .load(Ordering::Relaxed)
                {
                    let proxy = app.state::<crate::AppState>().proxy.clone();
                    let app = app.clone();
                    let stop_item = stop_item.clone();
                    tauri::async_runtime::spawn(async move {
                        let stopped = proxy.stop().await.is_ok() || proxy.is_alive().await.is_err();
                        if stopped {
                            app.state::<crate::AppState>().shutdown_child();
                            let _ = stop_item.set_enabled(false);
                        }
                    });
                }
            }
            "check-updates" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    updater::check_and_show(&app).await;
                });
            }
            "install-update" => {
                let app = app.clone();
                tauri::async_runtime::spawn(async move {
                    let update = app
                        .state::<crate::updater::PendingUpdate>()
                        .0
                        .lock()
                        .ok()
                        .and_then(|mut pending| pending.take());
                    let Some(update) = update else {
                        return;
                    };
                    let version = update.version.clone();
                    let retry_update = update.clone();
                    set_installing(&app, &version);
                    if let Err(error) = updater::install(&app, update).await {
                        if let Ok(mut pending) =
                            app.state::<crate::updater::PendingUpdate>().0.lock()
                        {
                            *pending = Some(retry_update);
                        }
                        set_install_failed(&app, &version);
                        crate::logging::log_once("updater install failed", &error);
                    }
                });
            }
            "quit" => app.exit(0),
            _ => {}
        })
        .build(app)?;

    refresh_title(&tray, &proxy);
    widget::refresh(&proxy);
    let tray = tray.clone();
    tauri::async_runtime::spawn(async move {
        let mut tick = 0;
        loop {
            tokio::time::sleep(std::time::Duration::from_secs(60)).await;
            refresh_title(&tray, &proxy);
            tick += 1;
            if tick % 5 == 0 {
                widget::refresh(&proxy);
            }
        }
    });
    Ok(())
}

pub fn show_update_available(app: &AppHandle, version: &str) {
    if let Some(state) = app.try_state::<TrayState>() {
        if let Ok(menu) = state.menu.lock() {
            if let Some(menu) = menu.as_ref() {
                let _ = menu.install_update.set_text(updater::update_label(version));
                let _ = menu.install_update.set_enabled(true);
                let _ = menu.check_updates.set_enabled(true);
                let _ = menu.check_updates.set_text("Check for Updates…");
            }
        }
    }
}

pub fn show_up_to_date(app: &AppHandle) {
    if let Some(state) = app.try_state::<TrayState>() {
        if let Ok(menu) = state.menu.lock() {
            if let Some(menu) = menu.as_ref() {
                let _ = menu
                    .check_updates
                    .set_text(format!("Up to date (v{})", env!("CARGO_PKG_VERSION")));
                let _ = menu.check_updates.set_enabled(true);
                let _ = menu.install_update.set_enabled(false);
            }
        }
    }
}

pub fn is_installing(app: &AppHandle) -> bool {
    app.try_state::<TrayState>()
        .is_some_and(|state| state.installing.load(Ordering::Acquire))
}

fn set_installing(app: &AppHandle, version: &str) {
    if let Some(state) = app.try_state::<TrayState>() {
        state.installing.store(true, Ordering::Release);
        if let Ok(menu) = state.menu.lock() {
            if let Some(menu) = menu.as_ref() {
                let _ = menu
                    .install_update
                    .set_text(format!("Installing update v{version}…"));
                let _ = menu.install_update.set_enabled(false);
                let _ = menu.check_updates.set_enabled(false);
            }
        }
    }
}

fn set_install_failed(app: &AppHandle, version: &str) {
    if let Some(state) = app.try_state::<TrayState>() {
        state.installing.store(false, Ordering::Release);
    }
    show_update_available(app, version);
}

fn refresh_title(tray: &tauri::tray::TrayIcon<Wry>, proxy: &ProxyClient) {
    let proxy = proxy.clone();
    let tray = tray.clone();
    tauri::async_runtime::spawn(async move {
        let app = tray.app_handle();
        let state = app.state::<TrayState>();
        // Skip overlapping manual/timer refreshes; the active refresh owns the display.
        let Ok(_refresh) = state.refresh.try_lock() else {
            return;
        };
        let settings = proxy.companion_settings().await.ok();
        let usage = if settings.is_some() {
            proxy.usage_today().await.unwrap_or(Value::Null)
        } else {
            Value::Null
        };
        let quotas = proxy.quotas().await.unwrap_or(Value::Null);
        if let Ok(mut menu) = state.menu.lock() {
            if let Some(menu) = menu.as_mut() {
                if let Some(settings) = settings {
                    menu.settings = settings;
                }
                let title = render_title(&menu.settings, &usage, &quotas);
                let _ = tray.set_title(title.as_deref());
                let today = render_today(&menu.settings, &usage);
                if let Some(text) = &today {
                    let _ = menu.today.set_text(text);
                }
                if today.is_some() != menu.today_visible {
                    let result = if today.is_some() {
                        menu.tray_menu.insert(&menu.today, 0)
                    } else {
                        menu.tray_menu.remove(&menu.today)
                    };
                    if result.is_ok() {
                        menu.today_visible = today.is_some();
                    }
                }
            }
        };
    });
}

fn usage_summary(usage: &Value) -> Option<&Value> {
    if usage.get("error").is_some_and(|error| !error.is_null()) {
        return None;
    }
    let summary = usage.get("summary").unwrap_or(usage);
    summary.is_object().then_some(summary)
}

fn measured_tokens(summary: &Value, key: &str) -> Option<i64> {
    if summary.get("measuredRequests").and_then(Value::as_i64) == Some(0)
        && summary.get("requests").and_then(Value::as_i64) != Some(0)
    {
        return None;
    }
    summary.get(key).and_then(Value::as_i64)
}

fn displayed_cost(summary: &Value) -> Option<f64> {
    if summary.get("pricedRequests").and_then(Value::as_i64) == Some(0)
        && summary.get("requests").and_then(Value::as_i64) != Some(0)
    {
        return None;
    }
    summary.get("estimatedCostUsd").and_then(Value::as_f64)
}

fn render_today(settings: &Value, usage: &Value) -> Option<String> {
    if settings
        .pointer("/settings/showToday")
        .and_then(Value::as_bool)
        == Some(false)
    {
        return None;
    }
    let Some(summary) = usage_summary(usage) else {
        return Some("Today · Unavailable".into());
    };
    let mut text = format!(
        "Today · {} tokens · {} requests",
        formatting::tokens(measured_tokens(summary, "totalTokens")),
        formatting::count(summary.get("requests").and_then(Value::as_i64)),
    );
    if settings
        .pointer("/settings/showCost")
        .and_then(Value::as_bool)
        != Some(false)
    {
        text.push_str(&format!(
            " · {} estimated",
            formatting::cost(displayed_cost(summary))
        ));
    }
    Some(text)
}

pub(crate) fn render_title(settings: &Value, usage: &Value, quotas: &Value) -> Option<String> {
    let metric = settings
        .pointer("/settings/menuBarMetric")
        .and_then(Value::as_str)
        .unwrap_or("tokens");
    let summary = usage_summary(usage).unwrap_or(&Value::Null);
    let quota = quota_percent(quotas);
    let value = match metric {
        "requests" => formatting::count(summary.get("requests").and_then(Value::as_i64)),
        "cost" => formatting::cost(displayed_cost(summary)),
        "quota" => format_percent(quota),
        "none" => return None,
        _ => formatting::tokens(measured_tokens(summary, "totalTokens")),
    };
    let template = settings
        .pointer("/settings/menuBarTemplate")
        .and_then(Value::as_str)
        .filter(|value| !value.trim().is_empty());
    let rendered = template
        .map(|value| {
            value
                .replace(
                    "{requests}",
                    &formatting::count(summary.get("requests").and_then(Value::as_i64)),
                )
                .replace(
                    "{totalTokens}",
                    &formatting::tokens(measured_tokens(summary, "totalTokens")),
                )
                .replace("{costUsd}", &formatting::cost(displayed_cost(summary)))
                .replace(
                    "{inputTokens}",
                    &formatting::tokens(measured_tokens(summary, "inputTokens")),
                )
                .replace(
                    "{outputTokens}",
                    &formatting::tokens(measured_tokens(summary, "outputTokens")),
                )
                .replace("{quotaPercent}", &format_percent(quota))
        })
        .unwrap_or(value);
    let rendered = rendered.trim();
    if rendered.is_empty() {
        None
    } else if rendered.chars().count() > 24 {
        Some(format!(
            "{}…",
            rendered.chars().take(23).collect::<String>()
        ))
    } else {
        Some(rendered.to_owned())
    }
}

fn quota_percent(value: &Value) -> Option<f64> {
    let reports = value.get("reports")?.as_array()?;
    let mut values = Vec::new();
    for report in reports {
        let Some(quota) = report.get("quota") else {
            continue;
        };
        for key in ["weeklyPercent", "monthlyPercent", "fiveHourPercent"] {
            if let Some(value) = quota.get(key).and_then(Value::as_f64) {
                values.push(value);
            }
        }
        if let Some(windows) = quota.get("customWindows").and_then(Value::as_array) {
            values.extend(
                windows
                    .iter()
                    .filter_map(|window| window.get("percent").and_then(Value::as_f64)),
            );
        }
    }
    values.into_iter().reduce(f64::min)
}

fn format_percent(value: Option<f64>) -> String {
    value
        .map(|value| format!("{}%", value.round() as i64))
        .unwrap_or_else(|| "—".into())
}

fn icon() -> tauri::image::Image<'static> {
    tauri::image::Image::from_bytes(include_bytes!("../icons/tray/icon.png"))
        .expect("valid tray icon")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn today_visibility_cost_and_metric_are_independent() {
        let usage =
            json!({"summary": {"requests": 2, "totalTokens": 1200, "estimatedCostUsd": 0.25}});
        assert_eq!(
            render_today(&Value::Null, &usage).as_deref(),
            Some("Today · 1K tokens · 2 requests · $0.25 estimated")
        );
        let settings = json!({"settings": {"showCost": false, "menuBarMetric": "none", "menuBarTemplate": "still hidden"}});
        assert_eq!(
            render_today(&settings, &usage).as_deref(),
            Some("Today · 1K tokens · 2 requests")
        );
        assert_eq!(render_title(&settings, &usage, &Value::Null), None);
        let settings = json!({"settings": {"showToday": false, "menuBarMetric": "requests"}});
        assert_eq!(render_today(&settings, &usage), None);
        assert_eq!(render_today(&settings, &Value::Null), None);
        assert_eq!(
            render_title(&settings, &usage, &Value::Null).as_deref(),
            Some("2")
        );
    }

    #[test]
    fn read_failure_is_not_an_empty_day() {
        let failure = json!({"error": "read_failed", "summary": {"requests": 0, "totalTokens": 0, "estimatedCostUsd": 0, "measuredRequests": 0, "pricedRequests": 0}});
        for usage in [&failure, &Value::Null] {
            assert!(usage_summary(usage).is_none());
            assert_eq!(
                render_today(&Value::Null, usage).as_deref(),
                Some("Today · Unavailable")
            );
            for metric in ["requests", "tokens", "cost"] {
                assert_eq!(
                    render_title(
                        &json!({"settings": {"menuBarMetric": metric}}),
                        usage,
                        &Value::Null
                    )
                    .as_deref(),
                    Some("—")
                );
            }
        }
        let empty = json!({"summary": {"requests": 0, "totalTokens": 0, "estimatedCostUsd": 0, "measuredRequests": 0, "pricedRequests": 0}});
        assert_eq!(
            render_today(&Value::Null, &empty).as_deref(),
            Some("Today · 0 tokens · 0 requests · $0.00 estimated")
        );
    }

    #[test]
    fn coverage_applies_to_title_templates_and_today() {
        let mut summary = json!({"requests": 2, "totalTokens": 0, "inputTokens": 0, "outputTokens": 0, "estimatedCostUsd": 0, "measuredRequests": 0, "pricedRequests": 0});
        let settings = json!({"settings": {"menuBarTemplate": "{inputTokens}/{outputTokens}/{totalTokens}/{costUsd}"}});
        assert_eq!(
            render_title(&settings, &summary, &Value::Null).as_deref(),
            Some("—/—/—/—")
        );
        assert_eq!(
            render_today(&Value::Null, &summary).as_deref(),
            Some("Today · — tokens · 2 requests · — estimated")
        );
        summary["measuredRequests"] = json!(1);
        summary["pricedRequests"] = json!(1);
        assert_eq!(
            render_title(&settings, &summary, &Value::Null).as_deref(),
            Some("0/0/0/$0.00")
        );
        summary.as_object_mut().unwrap().remove("measuredRequests");
        summary.as_object_mut().unwrap().remove("pricedRequests");
        assert_eq!(
            render_title(&settings, &summary, &Value::Null).as_deref(),
            Some("0/0/0/$0.00")
        );
    }

    #[test]
    fn quota_and_title_limit_keep_existing_contract() {
        let quotas = json!({"reports": [{"quota": {"weeklyPercent": 80, "fiveHourPercent": 20}}]});
        assert_eq!(
            render_title(
                &json!({"settings": {"menuBarMetric": "quota"}}),
                &Value::Null,
                &quotas
            )
            .as_deref(),
            Some("20%")
        );
        let settings = json!({"settings": {"menuBarTemplate": "가".repeat(25)}});
        let title = render_title(&settings, &Value::Null, &Value::Null).unwrap();
        assert_eq!(title.chars().count(), 24);
        assert!(title.ends_with('…'));
    }
}
