//! Dual offline-mode Azalea AFK bots for Paper + AuthMe (swarm).
//! Passwords from AUTHME_PASSWORD_FILE (nether) and AUTHME_PASSWORD_FILE_MAIN
//! (overworld). Never logs passwords.

use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::OnceLock;
use std::time::{Duration, Instant};

use azalea::auto_reconnect::{AutoReconnectDelay, DEFAULT_RECONNECT_DELAY};

use azalea::prelude::*;
use azalea::swarm::prelude::*;
use azalea::ClientInformation;
use parking_lot::Mutex;

const SERVER: &str = "127.0.0.1:25565";

const NETHER_USER: &str = "bot_nether1";
const MAIN_USER: &str = "bot_7e3a9c";

const NETHER_TP: &str = "/execute in minecraft:the_nether run tp @s 183.5 256 55.5";
const MAIN_TP: &str = "/execute in minecraft:overworld run tp @s -206.5 48.9375 -253.5";

static PASSWORDS: OnceLock<HashMap<String, String>> = OnceLock::new();

fn nether_password_path() -> PathBuf {
    env::var_os("AUTHME_PASSWORD_FILE")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/home/ytang/minecraft-afk-azalea/authme-password"))
}

fn main_password_path() -> PathBuf {
    env::var_os("AUTHME_PASSWORD_FILE_MAIN")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("/home/ytang/minecraft-afk-bot/authme-password"))
}

fn read_password(path: &PathBuf) -> eyre::Result<String> {
    let raw = fs::read_to_string(path)
        .map_err(|e| eyre::eyre!("failed to read {}: {e}", path.display()))?;
    let pw = raw.trim().to_string();
    if pw.is_empty() {
        eyre::bail!("{} is empty", path.display());
    }
    Ok(pw)
}

fn load_passwords() -> eyre::Result<&'static HashMap<String, String>> {
    if let Some(m) = PASSWORDS.get() {
        return Ok(m);
    }
    let mut map = HashMap::new();
    map.insert(NETHER_USER.to_string(), read_password(&nether_password_path())?);
    map.insert(MAIN_USER.to_string(), read_password(&main_password_path())?);
    let _ = PASSWORDS.set(map);
    Ok(PASSWORDS.get().unwrap())
}

fn password_for(username: &str) -> eyre::Result<&'static str> {
    let map = load_passwords()?;
    map.get(username)
        .map(|s| s.as_str())
        .ok_or_else(|| eyre::eyre!("no password for {username}"))
}

fn tp_for(username: &str) -> &'static str {
    if username == MAIN_USER {
        MAIN_TP
    } else {
        NETHER_TP
    }
}

fn now() -> String {
    use std::time::{SystemTime, UNIX_EPOCH};
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    format!("unix={secs}")
}

#[derive(Default)]
struct Inner {
    /// connection generation; bumped on every login packet / disconnect
    gen: u64,
    last_login_sent: Option<Instant>,
    authed: bool,
    tp_done: bool,
    consecutive_disconnects: u32,
}

#[derive(Clone, Component, Default)]
struct State {
    inner: Arc<Mutex<Inner>>,
}

const LOGIN_MIN_INTERVAL: Duration = Duration::from_secs(8);

fn set_reconnect_delay(bot: &Client, d: Duration) {
    bot.ecs.write().insert_resource(AutoReconnectDelay::new(d));
}

/// Send /login (rate limited) for the current generation, then tp shortly after.
fn send_login(bot: &Client, state: &State, username: &str, why: &str, register: bool) {
    let gen = {
        let mut i = state.inner.lock();
        if let Some(t) = i.last_login_sent {
            if t.elapsed() < LOGIN_MIN_INTERVAL {
                return;
            }
        }
        i.last_login_sent = Some(Instant::now());
        i.gen
    };
    let pw = match password_for(username) {
        Ok(p) => p.to_string(),
        Err(e) => {
            eprintln!("{} [{username}] {e}", now());
            return;
        }
    };
    let bot2 = bot.clone();
    let st = state.clone();
    let uname = username.to_string();
    let why = why.to_string();
    tokio::task::spawn_local(async move {
        tokio::time::sleep(Duration::from_millis(1200)).await;
        if st.inner.lock().gen != gen {
            return;
        }
        if register {
            bot2.chat(format!("/register {pw} {pw}"));
            tokio::time::sleep(Duration::from_millis(1500)).await;
            if st.inner.lock().gen != gen {
                return;
            }
        }
        bot2.chat(format!("/login {pw}"));
        println!("{} [{uname}] sent /login ({why}, gen={gen})", now());
        tokio::time::sleep(Duration::from_millis(2500)).await;
        send_tp(&bot2, &st, &uname, gen);
    });
}

fn send_tp(bot: &Client, state: &State, username: &str, gen: u64) {
    {
        let mut i = state.inner.lock();
        if i.gen != gen || i.tp_done {
            return;
        }
        // only mark done once auth confirmed; before that, tp may be blocked by AuthMe
        if i.authed {
            i.tp_done = true;
        }
    }
    bot.chat(tp_for(username).to_string());
    println!("{} [{username}] sent tp (gen={gen})", now());
}

#[derive(Clone, Default, Resource)]
struct SwarmState;

#[tokio::main]
async fn main() -> AppExit {
    if let Err(e) = load_passwords() {
        eprintln!("fatal: {e}");
        return AppExit::error();
    }

    println!(
        "{} starting azalea swarm: {NETHER_USER} + {MAIN_USER} -> {SERVER}",
        now()
    );

    SwarmBuilder::new()
        .set_handler(handle)
        .set_swarm_handler(swarm_handle)
        .add_account_with_state(Account::offline(NETHER_USER), State::default())
        .add_account_with_state(Account::offline(MAIN_USER), State::default())
        .join_delay(Duration::from_secs(3))
        .reconnect_after(DEFAULT_RECONNECT_DELAY)
        .set_swarm_state(SwarmState)
        .start(SERVER)
        .await
}

async fn handle(bot: Client, event: Event, state: State) -> eyre::Result<()> {
    let username = bot.username();
    match event {
        Event::Init => {
            let _ = bot.set_client_information(ClientInformation {
                view_distance: 2,
                ..Default::default()
            });
            println!("{} [{username}] init view_distance=2", now());
        }
        Event::Login => {
            {
                let mut i = state.inner.lock();
                i.gen += 1;
                i.last_login_sent = None;
                i.authed = false;
                i.tp_done = false;
            }
            println!("{} [{username}] login packet ok, new session", now());
            send_login(&bot, &state, &username, "login packet", false);
        }
        Event::Spawn => {
            println!("{} [{username}] spawned", now());
            let authed = state.inner.lock().authed;
            if !authed {
                send_login(&bot, &state, &username, "spawn", false);
            }
        }
        Event::Chat(m) => {
            let text = m.message().to_string();
            if text.len() < 240 {
                println!("{} [{username}] chat: {text}", now());
            }
            let lower = text.to_lowercase();
            let wants_register = lower.contains("/register") || lower.contains("please, register");
            let wants_login = lower.contains("please, login")
                || lower.contains("/login")
                || lower.contains("请登录")
                || lower.contains("登录");
            let success = lower.contains("successful login")
                || lower.contains("logged in")
                || lower.contains("already logged")
                || lower.contains("登录成功")
                || lower.contains("已登录")
                || lower.contains("session");
            if success {
                let gen = {
                    let mut i = state.inner.lock();
                    i.authed = true;
                    i.consecutive_disconnects = 0;
                    i.gen
                };
                set_reconnect_delay(&bot, DEFAULT_RECONNECT_DELAY);
                let bot2 = bot.clone();
                let st = state.clone();
                let uname = username.clone();
                tokio::task::spawn_local(async move {
                    tokio::time::sleep(Duration::from_millis(800)).await;
                    send_tp(&bot2, &st, &uname, gen);
                });
            } else if wants_register {
                send_login(&bot, &state, &username, "register prompt", true);
            } else if wants_login {
                let authed = state.inner.lock().authed;
                if !authed {
                    send_login(&bot, &state, &username, "login prompt", false);
                }
            }
        }
        Event::Disconnect(reason) => {
            let n = {
                let mut i = state.inner.lock();
                i.gen += 1;
                i.last_login_sent = None;
                i.authed = false;
                i.tp_done = false;
                i.consecutive_disconnects = i.consecutive_disconnects.saturating_add(1);
                i.consecutive_disconnects
            };
            // backoff: 5,10,20,40,60s cap
            let secs = (5u64 << (n.saturating_sub(1)).min(4)).min(60);
            set_reconnect_delay(&bot, Duration::from_secs(secs));
            eprintln!(
                "{} [{username}] disconnect: {reason:?}; reconnect in {secs}s (#{n})",
                now()
            );
        }
        _ => {}
    }
    Ok(())
}

async fn swarm_handle(_swarm: Swarm, event: SwarmEvent, _state: SwarmState) -> eyre::Result<()> {
    match event {
        SwarmEvent::Disconnect(account, _) => {
            eprintln!("{} swarm disconnect: {}", now(), account.username());
        }
        _ => {}
    }
    Ok(())
}
