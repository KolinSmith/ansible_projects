# deploy_print_server

Turns a Raspberry Pi (or any Debian host) into a CUPS print server for a
**USB-attached Brother HL-L2320D** laser printer, using the open `brlaser`
driver. Optionally shares the queue over Samba for Windows clients and keeps
Avahi running so Apple devices see it via AirPrint.

Extracted from the CUPS/Samba tasks that used to live inside
`provision_dev_server`, so a dedicated print-server host can be built without
the dev-server baggage.

## What it does

1. Installs `cups`, `cups-client`, `printer-driver-brlaser`, `avahi-daemon`.
2. Adds `{{ ansible_user }}` to `lpadmin` and runs
   `cupsctl --remote-any --share-printers`.
3. Auto-detects the USB device URI (`lpinfo -v`, first match on
   `print_server_usb_match`) unless `print_server_queue_uri` is set.
4. Creates the print queue with `lpadmin` (brlaser PPD), sets it as default.
5. (optional) Deploys a minimal print-only `smb.conf` — `[printers]` +
   `[print$]` only, **no** `[homes]` or file shares — and starts `smbd`/`nmbd`.
6. (optional) Ensures `avahi-daemon` is enabled for AirPrint discovery.

## Key variables

See `defaults/main.yml`. Most useful:

| var | default | note |
|---|---|---|
| `print_server_queue_name` | `Brother_HL-L2320D` | CUPS queue name |
| `print_server_queue_uri` | `""` | leave empty to auto-detect the USB URI |
| `print_server_queue_ppd` | `drv:///brlaser.drv/br2320d.ppd` | override if `lpadmin` rejects it |
| `print_server_samba_enabled` | `true` | print sharing for Windows |
| `print_server_airprint_enabled` | `true` | needs an mDNS reflector for cross-VLAN AirPrint |

## Notes

- If the print clients are on a different VLAN than this host, the router
  needs an **mDNS/Avahi reflector** (Bonjour is link-local) plus firewall
  rules allowing the clients to reach TCP 631 (IPP) and 445/139 (SMB). See
  `dotfiles/.claude/plans/2026-09-05-print-server-migration-and-rebuild.md`.
