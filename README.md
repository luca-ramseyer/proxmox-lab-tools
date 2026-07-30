# proxmox-lab-tools

Scripts for running isolated, multi-tenant network labs on a single Proxmox VE
host.

Each **lab pod** is a self-contained mini-datacenter: its own firewall, its own
LAN / DMZ / Server segments, its own Proxmox pool and user. Pods cannot reach
each other. One person can break everything inside their pod without touching
anyone else's.

Built for teaching — one pod per student, plus one for the instructor.

---

## Contents

| Script | Purpose |
|---|---|
| `new-lab.sh` | Provision a complete lab pod: bridges, pool, user, firewall |
| `add-vms.sh` | Clone the guest VMs into an existing pod and pin them to zone bridges |

More tooling to follow (see [Roadmap](#roadmap)).

---

## Concept

A Linux bridge with no physical port is an isolated virtual switch. Each pod
gets three of them — LAN, DMZ, Server — and nothing routes between those zones
except that pod's own OPNsense firewall. The only shared resource is `vmbr0`,
the uplink every firewall NATs out through.

```
                    vmbr0  (uplink to the real network)
                      |
        +-------------+-------------+
        |                           |
   fw-01.raml                  fw-01.busd          <- one OPNsense per pod
   (VM 1000)                   (VM 2000)
    |    |    |                 |    |    |
 vmbr11 12   13             vmbr21 22   23         <- portless, fully isolated
  LAN  DMZ  SRV              LAN  DMZ  SRV
```

### Naming and addressing

Everything encodes the lab number, so any bridge, VMID, or IP address tells you
immediately which pod and which zone it belongs to.

| Lab | Bridges (LAN/DMZ/SRV) | Subnets | VMID range | Firewall |
|---|---|---|---|---|
| 1 | `vmbr11` `vmbr12` `vmbr13` | `10.1.10/20/30.0/24` | 1000–1999 | 1000 |
| 2 | `vmbr21` `vmbr22` `vmbr23` | `10.2.10/20/30.0/24` | 2000–2999 | 2000 |
| 3 | `vmbr31` `vmbr32` `vmbr33` | `10.3.10/20/30.0/24` | 3000–3999 | 3000 |

Bridge naming: `vmbr<lab><zone>` where zone is 1 = LAN, 2 = DMZ, 3 = Server.
Subnets: `10.<lab>.<zone*10>.0/24`. The firewall always holds `.1` in each zone.

The firewall hostname is `fw-01` in every pod; the domain disambiguates:
`fw-01.<user>.lab.raml.ch`.

Non-firewall infrastructure lives outside the pod ranges (100–199) and
templates at 9000+.

---

## Prerequisites

These must exist before `new-lab.sh` will work.

**1. An OPNsense golden template (default VMID `9100`).**

Build one firewall by hand, then convert it to a template. It must have:

- Four VirtIO NICs in this order — `net0` WAN, `net1` LAN, `net2` DMZ,
  `net3` SRV. OPNsense assigns interfaces by device name (`vtnet0..3`), not
  MAC, so this ordering carries correctly into every clone.
- WAN and LAN configured; DMZ configured with its rule set.
- **SRV / OPT2 left completely unassigned** — the NIC is wired but the
  interface is not assigned, addressed, or ruled. This is deliberate: bringing
  the Server zone up is the student exercise.
- The `os-qemu-guest-agent` plugin installed and `qemu_guest_agent_enable="YES"`
  set, plus **Options → QEMU Guest Agent** ticked on the Proxmox side. The
  provisioning script needs this to set the per-pod domain.
- WAN interface has *Block private networks* enabled, so pod firewalls cannot
  reach each other across the shared uplink.

**2. A `LabUser` role** (Datacenter → Permissions → Roles → Create):

`VM.Audit`, `VM.Console`, `VM.PowerMgmt`, `VM.Snapshot`,
`VM.Snapshot.Rollback`, `VM.Config.CDROM`

Deliberately excluded: `VM.Config.Network` — without it a student cannot
re-attach their VM to a different bridge and bypass their firewall. Also no
`Sys.*`, so there is no path from a lab account to the hypervisor.

**3. Linux guest templates** for lab VMs (e.g. `9000` desktop, `9001` server).

---

## Install

```bash
apt install -y git
git clone https://github.com/<you>/proxmox-lab-tools.git /opt/proxmox-lab-tools
ln -s /opt/proxmox-lab-tools/new-lab.sh /usr/local/bin/new-lab
```

To always run the latest version, use a wrapper at `/usr/local/bin/new-lab`
instead of the symlink:

```bash
#!/usr/bin/env bash
git -C /opt/proxmox-lab-tools pull --quiet
exec /opt/proxmox-lab-tools/new-lab.sh "$@"
```

---

## Usage

```bash
new-lab -n <1-9> -u <username> [-p <password>] [--dry-run]
```

| Flag | Meaning |
|---|---|
| `-n` | Lab number. Drives bridge names, subnets and VMIDs. |
| `-u` | Short username. Becomes pool `lab-<user>`, PVE user `<user>@pve`, and domain `<user>.lab.raml.ch`. |
| `-p` | Password for the new PVE user. Prompted if omitted. Pass `-p ''` to skip user creation. |
| `--dry-run` | Print every action, change nothing. |

Always dry-run an unfamiliar lab number first:

```bash
new-lab -n 2 -u busd --dry-run
new-lab -n 2 -u busd
```

### What it does

1. Preflight — must be root, template must exist, VMID must be free
2. Backs up `/etc/network/interfaces`, appends three portless bridges,
   `ifreload -a`
3. Creates pool `lab-<user>`
4. Full-clones the firewall template into the pod's VMID, pins its four NICs to
   the right bridges, enables the guest agent and `onboot`
5. Boots the firewall, waits for the guest agent, patches `<hostname>` and
   `<domain>` in `/conf/config.xml`, reboots it
6. Creates the PVE user and grants `LabUser` on the pod's pool

Existing bridges, pools and users are detected and skipped, so a partially
failed run is safe to repeat.

### After provisioning

The firewall is running but nothing else is on the pod's LAN yet. `add-vms.sh`
clones the standard guest roster in and wires each one to its zone bridge:

```bash
add-vms.sh -n 2 -u busd --dry-run
add-vms.sh -n 2 -u busd
```

| Guest | Template | Zone | Bridge (lab 2) |
|---|---|---|---|
| `ubu-de-01` | Ubuntu desktop | LAN | `vmbr21` |
| `win11-01` | Windows 11 | LAN | `vmbr21` |
| `kali-01` | Kali | LAN | `vmbr21` |
| `ubu-srv-dmz` | Ubuntu server | DMZ | `vmbr22` |
| `ubu-srv-srv` | Ubuntu server | SRV | `vmbr23` |

VMIDs are assigned from `<lab>010` upwards. Names get a `-lab<n>` suffix, and
that name is how a re-run knows a guest already exists — so an interrupted run
is safe to repeat and only the missing guests get created.

Guests are created stopped; pass `--start` to power them on, or `--only a,b` to
create a subset. Template VMIDs live in a config block at the top of the script
— **check them against `qm list` before the first real run.**

The SRV guest has no gateway until the student assigns and addresses OPT2 in
OPNsense. That is the exercise.

Then browse to `https://10.2.10.1` from a LAN client to reach the OPNsense GUI.

---

## Safety notes

- `new-lab.sh` writes to `/etc/network/interfaces` on the hypervisor. It backs
  the file up first (`.bak.<timestamp>`), but review a `--dry-run` before
  trusting a new version.
- `-p` puts a password in your shell history. Prefer the interactive prompt.
- Every pod firewall's WAN sits on the real network. *Block private networks*
  on WAN is what keeps pods from reaching each other there — verify it in the
  template.
- The Proxmox host has no IP on any pod bridge, by design. It cannot route
  around a pod firewall, and neither can anything else.

---

## Roadmap

- `rm-lab.sh` — tear down a pod: stop and destroy its VMs, drop the pool, user,
  ACLs and bridges
- `lab-status.sh` — show every pod, its VMs, and their power state
- Migration to a VLAN-aware bridge, replacing per-pod bridges with per-pod VLAN
  ranges — the same isolation, but the way it is actually done in production
