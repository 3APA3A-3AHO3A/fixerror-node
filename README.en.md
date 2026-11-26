# fixerror-node

[Русский](README.md) | English

A Remnawave node installer for FixErrorVPN. It builds a node to the same template as every other node of the service:
- an admin account with SSH hardening, plus a separate account for AI agents;
- a firewall with torrent blocking, fail2ban;
- protection from RKN probers: new inbound connections from government and scanner networks are dropped, the lists are refreshed daily;
- a shared sysctl template, MTU measurement and pinning, UTC time;
- Docker and the node container with Loyalsoldier geo databases; the Xray core updates them itself, without restarting the node;
- Xray egress options: WARP on port 6000, warp-native, Psiphon;
- for Grafana graphs and bookkeeping: node_exporter (port 9100 for the monitoring server only), vnstat, etckeeper, lynis, mtr;
- nginx with the tools site;
- **node-pull**: the node fetches its certificate and site from the panel;
- Telegram notifications via `remnawave-notify` (mandatory);
- an optional xray client for Telegram on Russian nodes, configured from a subscription.

One downloaded file covers the node's whole life cycle: install, diagnostics, targeted repair.

The framework (tmux, apt waiting, SSH checks, menu, diagnostics, repair, tests) comes from [rabotahrista](https://github.com/3APA3A-3AHO3A/rabotahrista). What differs is specific to FixError nodes: the certificate comes from the panel instead of Let's Encrypt, notifications use `remnawave-notify`, and all settings follow the shared template.

## Install

```bash
sudo curl -fsSL https://raw.githubusercontent.com/3APA3A-3AHO3A/fixerror-node/main/setup.sh -o /tmp/setup.sh
sudo bash /tmp/setup.sh
```

Do a full system upgrade and reboot first. The installer upgrades packages itself, but a new kernel only takes effect after a reboot.

Root is required. `sudo bash <(curl ...)` does not work, because sudo closes extra file descriptors.

The script asks every question up front, then runs unattended. If SSH drops, the install keeps going inside tmux; reattach with `sudo tmux attach -t fixerror`. At the end it prints a report and saves it to `/root/node-install-report.txt`.

Unattended, with an answers file (see [config.example.conf](config.example.conf)):

```bash
sudo bash /tmp/setup.sh /root/node.conf
```

### What it asks

| What | Example |
|---|---|
| Panel IP | 203.0.113.10 |
| Node SECRET_KEY from the panel | — |
| Node name (Telegram and the panel line) | Finland 3 hshp |
| Node role | `reality` (regular) or `cdn` (origin behind a CDN: domain, XHTTP path and port) |
| Node image version | Enter means latest |
| Account, password, SSH port | vadim, random, 8422 |
| SSH public key and extra keys | — |
| AI agent key | Enter means no agent |
| WARP, warp-native, Psiphon, Speedtest, geo databases, protection from RKN probers | yes by default |
| Own xray client for Telegram and its subscription link | no by default; needed on Russian nodes |
| Telegram: token, chat, topic, proxy | mandatory; with the own xray client the proxy is filled in automatically |

## After install: the node key on the panel

The `*.safeline24.com` certificate and the tools site sit on the panel in `/var/lib/node-pull/bundle.tar.gz`. The node fetches that bundle over SSH with its own key. The installer creates the key; you add the matching line on the panel. The report prints it ready to paste:

```bash
# on the panel
echo 'restrict,from="NODE_IP",command="/bin/cat /var/lib/node-pull/bundle.tar.gz" ssh-ed25519 AAAA... node-pull Finland 3 hshp' \
  | sudo tee -a /var/lib/node-pull/.ssh/authorized_keys
# on the node
sudo node-pull        # → "обновлено: сертификат сайт"
```

The line allows exactly one thing: fetching the bundle, and only from this node's IP. Until you add it, nginx runs with a temporary self-signed certificate. After that, `node-pull.timer` checks the bundle every 6 hours and after boot, and installs updates on its own. Menu item 2 → 22 shows the line again.

The installer fetches the panel's host key from the panel itself and prints its fingerprint. Compare it on the panel with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`. To skip that check, put the key into `PANEL_HOSTKEY` in the answers file.

## Main menu

| Item | What it does | Changes the system |
|---|---|---|
| 1. Full install | All steps in order, then a reboot | Yes, everything |
| 2. Components | One step of your choice | Yes, that step |
| 3. Diagnostics | Checks the node and lists problems | No |
| 4. Repair | Shows a plan, asks, then fixes common breakages | Yes, after you confirm |
| 5. Diagnostics + panel | Same as 3, plus a check that the panel serves this node | No |

The same without the menu:

```bash
sudo bash /tmp/setup.sh --check     # diagnostics
sudo bash /tmp/setup.sh --repair    # repair without questions
```

`check.sh` is a standalone diagnostics-only script. A test guarantees it never changes anything.

Repair works from a fixed list. It prints a plan first, then waits for your answer:
- mode 600 on secret files: answers, Telegram token, node-pull key, certificate key, compose file;
- SSH hardening, only when `sshd -T` shows root or password login open;
- docker group membership for the admin account;
- `remnawave-notify`, its service, `@reboot` and the PAM line;
- the node-pull script and timer;
- geo databases in the old layout (per-file mounts and the geo-update timer) are moved to a directory the core updates; the node container is recreated, about 10 seconds of downtime.

Repair never touches the firewall or the nginx site config, and never reboots. The node container is recreated only by the geo databases item.

## What gets installed

| What | How |
|---|---|
| SSH | `/etc/ssh/sshd_config.d/00-hardening.conf`: port 8422, root and passwords off, agent and TCP forwarding off, verbose login log (`LogLevel VERBOSE`). `Port` is written only if the main `sshd_config` lacks it: two identical `Port` lines cause "Address already in use" |
| UFW | 8422/tcp, 80/tcp, 443/tcp, 443/udp; 2222/tcp from the panel IP only; 9100/tcp (node_exporter) from `MONITOR_IP` only (empty means the panel IP); plus `UFW_EXTRA_PORTS`. SSH uses allow, not limit: limit cuts off agents that open many short sessions, brute force is impossible anyway (keys only), and fail2ban handles the rest |
| Torrents | 6 `-m string` rules in `/etc/ufw/before.rules`, placed before ESTABLISHED |
| RKN probers | see below |
| fail2ban | sshd: 4 tries → 24 h ban; recidive: 1 week |
| sysctl | `/etc/sysctl.d/99-vpn-tune.conf`: BBR/fq, 16 MB buffers, conntrack 262144, reserved ports 8422, 2222, 9443, 6000, IPv6 off |
| MTU | path measured with don't-fragment pings; below 1500 it is pinned by `mtu-<iface>` and set in `daemon.json` |
| Docker | `daemon.json`: log rotation 10 MB × 3; systemd journal capped at 1 GB |
| Node | `/opt/remnanode/docker-compose.yml`, host network, the `/opt/remnanode/geodata` directory mounted whole and writable; the node directory belongs to the admin account |
| Geo databases | the installer puts them in place once (sha256 checked). After that the Xray core updates them from the `geodata` block in the panel config profile: downloads next to the file, renames it into place and reloads without a restart. The installer prints the block at the end of the step; you add it to the profile yourself |
| Site | Reality: `stub.conf` (self-steal on 127.0.0.1:9443, PROXY protocol). CDN: `<domain>.conf` (443, site + XHTTP to Xray) |
| node-pull | `/usr/local/sbin/node-pull`, keys in `/etc/node-pull`, `node-pull.timer` |
| Notifications | `/usr/local/sbin/remnawave-notify` (the same script as on the panel), `/etc/remnawave-notify.env`, `remnawave-notify-watch.service`, `@reboot`, PAM |
| Time | UTC, chrony |
| Bookkeeping and audit | `prometheus-node-exporter` (Grafana graphs), `vnstat` (traffic), `etckeeper` (`/etc` history in git), `lynis` (daily audit), `mtr-tiny` |

### Protection from RKN probers

DPI probers and scanners connect to a node like clients and recognise a VPN by its answer. The node does not answer them: inbound connections from government and scanner networks are dropped. The networks come from three lists of [shadow-netlab/traffic-guard-lists](https://github.com/shadow-netlab/traffic-guard-lists): `government_networks`, `antiscanner`, `skipa` (about 2,900 IPv4 and 30 IPv6 networks). These are the same lists rkn-guard uses, without its program and panel: just ipset and a ufw rule.

- Only **new** inbound connections are dropped. Replies to connections the node opened itself pass, so clients on nodes that send all traffic through the VPN can still open government sites.
- The panel IP is never blocked. On CDN nodes the installer also exempts the CDN provider networks (`188.72.110.0/22` by default, can be changed), because clients arrive from there. Your own exceptions (e.g. a Russian server that forwards traffic to the node) go into `/etc/fixerror-node/rkn-allow.txt`, one per line; then run `sudo rkn-block`. At install time they can be set in `RKN_ALLOW`.
- Updates: `/usr/local/sbin/rkn-block` + `rkn-block.timer`, daily at 02:30 UTC ± 1 h. A broken list (fewer than 500 networks), a failed download and networks wider than /16 are rejected: the sets stay as they were, and the failure is reported to Telegram at most once a day.
- After a reboot the sets are restored from a saved copy before ufw starts (`rkn-block-restore.service`, drop-in `ufw.service.d/rkn-block.conf`). Otherwise a rule that refers to a missing set would stop ufw from starting.
- To see what would go into the sets without changing anything: `sudo rkn-block --print`. To turn it off: menu item 2 → 28 → 2.

### Own xray client for Telegram (Russian nodes)

api.telegram.org is blocked from Russia, so node notifications go through a separate xray. The installer asks whether to install it (no by default) and asks for a FixErrorVPN subscription link of a service user (e.g. MONITORING).

- Xray comes from the official XTLS release, checked against its SHA-256. It listens only on `127.0.0.1:10808` (socks) and `10809` (http); `TG_PROXY` defaults to `socks5h://127.0.0.1:10808`.
- The config is "Автовыбор" (AutoBalancer template) from the subscription: Russian traffic goes direct, everything else via the best live server. `xray-sub-update.timer` refreshes it every 6 hours and 5 minutes after boot.
- A new config is applied only if it passes `xray -test` and Telegram opens through it; otherwise the old one stays, and the failure is reported to Telegram at most once a day. Log: `journalctl -t xray-sub`.
- Geo databases are shared with the node (`/opt/remnanode/geodata`), so they are always enabled together with the client.

## Development

`setup.sh` and `check.sh` are build outputs; never edit them by hand. The sources live in `lib/`, and `build.py` concatenates them in file-name order.

```bash
git config core.hooksPath .githooks   # once
git commit -m "..."                   # the hook rebuilds setup.sh/check.sh and runs the tests
```

Run the tests with `bash tests/run-tests.sh`; they need no server. Besides syntax and shellcheck, they cover:
- the sysctl, SSH and torrent templates;
- the site config for both roles, and rollback when `nginx -t` fails;
- the panel key line;
- that `remnawave-notify` matches the reference `tests/remnawave-notify.ref` byte for byte;
- the first geo database download (a broken file never replaces a working one) and moving the compose mount to a directory;
- protection from RKN probers: list parsing, exceptions, rejecting a broken list, restoring the sets at boot;
- that diagnostics change nothing.

If `remnawave-notify` changes on the panel, update both the reference file and `lib/80-notify.sh`.
