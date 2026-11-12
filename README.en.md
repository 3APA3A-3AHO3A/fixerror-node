# fixerror-node

[Русский](README.md) | English

A Remnawave node installer for FixErrorVPN. It builds a node to the same template as every other node of the service:
- an admin account with SSH hardening, plus a separate account for AI agents;
- a firewall with torrent blocking, fail2ban;
- a shared sysctl template, MTU measurement and pinning, UTC time;
- Docker and the node container with Loyalsoldier geo databases, updated every 3 days;
- Xray egress options: WARP on port 6000, warp-native, Psiphon;
- nginx with the tools site;
- **node-pull**: the node fetches its certificate and site from the panel;
- Telegram notifications via `remnawave-notify`.

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
| WARP, warp-native, Psiphon, Speedtest, geo databases | yes by default |
| Telegram: token, chat, topic, proxy | nodes in Russia: `socks5h://127.0.0.1:10808` |

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
- the geo-update script and timer.

Repair never touches the firewall, the container or the nginx site config, and never reboots.

## What gets installed

| What | How |
|---|---|
| SSH | `/etc/ssh/sshd_config.d/00-hardening.conf`: port 8422, root and passwords off. `Port` is written only if the main `sshd_config` lacks it: two identical `Port` lines cause "Address already in use" |
| UFW | 8422/tcp (limit), 80/tcp, 443/tcp, 443/udp; 2222/tcp from the panel IP only; plus `UFW_EXTRA_PORTS` |
| Torrents | 6 `-m string` rules in `/etc/ufw/before.rules`, placed before ESTABLISHED |
| fail2ban | sshd: 4 tries → 24 h ban; recidive: 1 week |
| sysctl | `/etc/sysctl.d/99-vpn-tune.conf`: BBR/fq, 16 MB buffers, conntrack 262144, reserved ports 8422, 2222, 9443, 6000, IPv6 off |
| MTU | path measured with don't-fragment pings; below 1500 it is pinned by `mtu-<iface>` and set in `daemon.json` |
| Docker | `daemon.json`: log rotation 10 MB × 3; systemd journal capped at 1 GB |
| Node | `/opt/remnanode/docker-compose.yml`, host network, geo databases mounted from `/opt/remnanode/geodata` |
| Geo databases | `/usr/local/sbin/geo-update` + `geo-update.timer`: every 3 days at 01:00 UTC ± 15 min; sha256 check; the node restarts only when the databases changed |
| Site | Reality: `stub.conf` (self-steal on 127.0.0.1:9443, PROXY protocol). CDN: `<domain>.conf` (443, site + XHTTP to Xray) |
| node-pull | `/usr/local/sbin/node-pull`, keys in `/etc/node-pull`, `node-pull.timer` |
| Notifications | `/usr/local/sbin/remnawave-notify` (the same script as on the panel), `/etc/remnawave-notify.env`, `remnawave-notify-watch.service`, `@reboot`, PAM |
| Time | UTC, chrony |

The installer does not set up the separate xray that Russian nodes use for Telegram. If you need it, put its address into `TG_PROXY`.

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
- safe geo database updates;
- that diagnostics change nothing.

If `remnawave-notify` changes on the panel, update both the reference file and `lib/80-notify.sh`.
