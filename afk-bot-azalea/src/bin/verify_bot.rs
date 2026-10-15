//! Single test bot for restore verification. Env: VERIFY_SERVER (host:port),
//! VERIFY_USER, VERIFY_PASSWORD, VERIFY_SECONDS. Prints SPAWNED / AUTH_OK /
//! POS lines; exits 0 if spawned and never disconnected, else 1.
use std::env;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;
use azalea::prelude::*;
use azalea::ClientInformation;

static SPAWNED: AtomicBool = AtomicBool::new(false);
static DISCONNECTED: AtomicBool = AtomicBool::new(false);
static STARTED: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Component, Default)]
struct State;

fn pw() -> String { env::var("VERIFY_PASSWORD").unwrap_or_else(|_| "verifyPw123".into()) }

#[tokio::main]
async fn main() -> AppExit {
    let server = env::var("VERIFY_SERVER").unwrap_or_else(|_| "127.0.0.1:25599".into());
    let user = env::var("VERIFY_USER").unwrap_or_else(|_| "verify_bot".into());
    let secs: u64 = env::var("VERIFY_SECONDS").ok().and_then(|s| s.parse().ok()).unwrap_or(120);
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_secs(secs)).await;
        let ok = SPAWNED.load(Ordering::SeqCst) && !DISCONNECTED.load(Ordering::SeqCst);
        println!("RESULT {}", if ok { "PASS" } else { "FAIL" });
        std::process::exit(if ok { 0 } else { 1 });
    });
    println!("connecting {user} -> {server}");
    ClientBuilder::new()
        .set_handler(handle)
        .start(Account::offline(&user), server.as_str())
        .await
}

async fn handle(bot: Client, event: Event, _s: State) -> eyre::Result<()> {
    match event {
        Event::Init => {
            let _ = bot.set_client_information(ClientInformation { view_distance: 4, ..Default::default() });
        }
        Event::Login => println!("LOGIN"),
        Event::Spawn => {
            SPAWNED.store(true, Ordering::SeqCst);
            println!("SPAWNED");
            if !STARTED.swap(true, Ordering::SeqCst) {
                let b = bot.clone();
                tokio::task::spawn_local(async move {
                    let p = pw();
                    tokio::time::sleep(Duration::from_millis(1500)).await;
                    b.chat(format!("/register {p} {p}"));
                    tokio::time::sleep(Duration::from_millis(2500)).await;
                    b.chat(format!("/login {p}"));
                    loop {
                        tokio::time::sleep(Duration::from_secs(5)).await;
                        let Ok(pos) = b.position() else { println!("POS none"); continue; };
                        println!("POS {:.1} {:.1} {:.1}", pos.x, pos.y, pos.z);
                    }
                });
            }
        }
        Event::Chat(m) => {
            let t = m.message().to_string();
            if t.len() < 300 { println!("CHAT {t}"); }
        }
        Event::Disconnect(r) => {
            DISCONNECTED.store(true, Ordering::SeqCst);
            println!("DISCONNECT {r:?}");
        }
        _ => {}
    }
    Ok(())
}
