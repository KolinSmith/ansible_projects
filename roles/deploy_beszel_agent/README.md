# deploy_beszel_agent

Installs the [Beszel](https://beszel.dev) monitoring agent as a **native
systemd service**, for hosts that don't run Docker. Docker hosts use the
`beszel-agent` container in `docker_projects` instead.

## What it does

1. Creates a `beszel` system user (nologin).
2. Downloads the `beszel-agent` release binary for the host's architecture
   into `/opt/beszel-agent/`.
3. Installs `/etc/systemd/system/beszel-agent.service` with `LISTEN`, `KEY`,
   and `TOKEN` from the hub, then enables and starts it.

## Variables

| var | default | note |
|---|---|---|
| `beszel_agent_version` | `latest` | or a pinned release tag |
| `beszel_agent_listen_port` | `45876` | TCP port the hub connects to |
| `beszel_agent_key` | `{{ docker_beszel_agent_key }}` | hub SSH public key (vault) |
| `beszel_agent_token` | `{{ docker_beszel_agent_token }}` | agent token (vault) |

## After running

Add the host in the Beszel hub UI (on voyager) pointing at
`<host>:45876` so the hub starts collecting from it. Both hosts are on the
`192.168.9.x` server VLAN, so no pfSense rule is needed.
