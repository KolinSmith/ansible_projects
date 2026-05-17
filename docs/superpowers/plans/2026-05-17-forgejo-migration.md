# Forgejo Migration (ansible_projects) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate `ansible_projects` to Forgejo as the primary remote with GitHub as an automatic push mirror, and add a full CI suite (yaml-lint, ansible-lint, checkov, gitleaks, shellcheck, ruff, scc).

**Architecture:** Create a reusable migration shell script that calls the Forgejo API and rewires git remotes. Add Forgejo Actions CI workflow and Gitleaks config as files in the repo. Run the migration script to create the Forgejo repo and wire everything up. Then lock down both sides with branch protection.

**Tech Stack:** Bash, Forgejo API, Forgejo Actions, wolfi-base (cgr.dev/chainguard/wolfi-base), yamllint, ansible-lint, checkov, gitleaks, shellcheck, ruff, scc

---

## Repo State Matrix (for all homelab repos)

| Repo | Forgejo state | Action needed |
|------|---------------|---------------|
| `docker_projects` | ✅ primary | none — already migrated |
| `dotfiles` | ✅ primary | none — already migrated |
| `ansible_projects` | deleted (was pull mirror) | recreate via script |
| `terraform_projects` | pull mirror | script will detect + convert |
| `cloudflare_blueprint` | doesn't exist | script will create |

---

## Forgejo Token Requirements

The token in `~/.homelab-secrets/forgejo.env` needs these scopes:
- **`write:user`** — required for `POST /api/v1/user/repos` (create repos)
- **`write:repository`** — required for push mirrors, branch protection

Regenerate at: `https://git.hiddenba.se/user/settings/applications`

The migration script (`scripts/migrate-to-forgejo.sh`) probes `write:user` scope before any destructive operations — it will exit with a clear error if the token is missing the scope.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `scripts/migrate-to-forgejo.sh` | ✅ Created | Reusable idempotent script: detects pull mirrors, creates repo, pushes history, sets up push mirror, rewires remotes |
| `.forgejo/workflows/validate.yml` | ✅ Created | CI: 7 parallel jobs on PRs and non-master pushes |
| `.gitleaks.toml` | ✅ Created | Excludes vault.yml from Gitleaks secrets scan |

---

## Task Status

| Task | Status |
|------|--------|
| Task 1: Create feature branch | ✅ Done |
| Task 2: Create migration script | ✅ Done (script updated with idempotency + pull mirror handling) |
| Task 3: Create .gitleaks.toml | ✅ Done |
| Task 4: Create CI workflow | ✅ Done |
| Task 5: Run migration script | ⏳ Blocked — regenerate Forgejo token first |
| Task 6: Push branch + open PR | ⏳ Pending |
| Task 7: Verify CI passes | ⏳ Pending |
| Task 8: Forgejo branch protection | ⏳ Pending |
| Task 9: GitHub bypass | ⏳ Pending |
| Task 10: Merge + verify mirror | ⏳ Pending |

---

### Task 5: Run the migration script

**Prerequisites:**
- [ ] Forgejo token regenerated with `write:user` + `write:repository` scopes
- [ ] `FORGEJO_TOKEN` updated in `~/.homelab-secrets/forgejo.env`

**Steps:**

- [ ] **Step 1: Decrypt the GitHub PAT from vault**

```bash
cd /home/dax/code_base/ansible_projects
GITHUB_PAT=$(ansible-vault view group_vars/all/vault.yml \
  --vault-id /home/dax/code_base/dotfiles/.ansible_password \
  | grep vault_github_personal_access_token \
  | awk '{print $2}')
echo "PAT starts with: ${GITHUB_PAT:0:15}..."
```

- [ ] **Step 2: Run the migration script**

```bash
GITHUB_PAT="${GITHUB_PAT}" ./scripts/migrate-to-forgejo.sh ansible_projects
```

Expected output:
```
==> Migrating ansible_projects to Forgejo...
--> Checking Forgejo repo state...
    Token scope verified.
    Pull mirror deleted.        ← or "Repo already exists as primary"
--> Creating repo on Forgejo...
    Created: https://git.hiddenba.se/dax/ansible_projects
--> Pushing all branches and tags to Forgejo...
    Pushed all branches and tags.
--> Configuring push mirror: Forgejo -> GitHub...
    Push mirror configured: Forgejo -> GitHub (syncs on every commit)
--> Rewiring origin remote...

==> Migration complete for ansible_projects!
```

- [ ] **Step 3: Verify remotes**

```bash
git remote -v
```

Expected:
```
forgejo  ssh://git@100.86.4.29:222/dax/ansible_projects.git (fetch)
forgejo  ssh://git@100.86.4.29:222/dax/ansible_projects.git (push)
origin   https://github.com/KolinSmith/ansible_projects.git (fetch)
origin   ssh://git@100.86.4.29:222/dax/ansible_projects.git (push)
```

---

### Task 6: Push branch to Forgejo and open PR

- [ ] **Step 1: Push the feature branch**

```bash
cd /home/dax/code_base/ansible_projects
git push origin feat/forgejo-migration
```

`origin` push now points to Forgejo, so this pushes to Forgejo.

- [ ] **Step 2: Open a PR via Forgejo API**

```bash
source ~/.homelab-secrets/forgejo.env
curl -s -X POST "${FORGEJO_URL}/api/v1/repos/dax/ansible_projects/pulls" \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "feat: add Forgejo CI and migration script",
    "head": "feat/forgejo-migration",
    "base": "master",
    "body": "Adds migration script, CI workflow (yaml-lint, ansible-lint, checkov, gitleaks, shellcheck, ruff, scc), and gitleaks vault exclusion."
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('PR:', d.get('html_url',''))"
```

---

### Task 7: Verify CI passes — fix failures

- [ ] **Step 1: Watch CI on Forgejo**

Go to `https://git.hiddenba.se/dax/ansible_projects/actions` and watch all 7 jobs.
All 6 blocking jobs must be green. `scc` (informational) may be skipped — that's fine.

- [ ] **Step 2: If ansible-lint fails**

Create `/home/dax/code_base/ansible_projects/.ansible-lint`:
```yaml
warn_list:
  - yaml[truthy]
  - name[casing]
  - fqcn[action-core]
  - no-changed-when
  - risky-shell-pipe
  - command-instead-of-module
  - command-instead-of-shell

skip_list:
  - galaxy

exclude_paths:
  - group_vars/all/vault.yml
  - .git/
```

```bash
git add .ansible-lint
git commit -m "chore: add ansible-lint config suppressing noisy rules"
git push origin feat/forgejo-migration
```

- [ ] **Step 3: If checkov fails**

Create `/home/dax/code_base/ansible_projects/.checkov.yaml`:
```yaml
skip-check:
  - CKV_ANSIBLE_2   # replace with actual check IDs from output
```

Commit and push the same way.

- [ ] **Step 4: Confirm all blocking checks green before proceeding**

---

### Task 8: Configure Forgejo branch protection

- [ ] **Step 1: Enable via API**

```bash
source ~/.homelab-secrets/forgejo.env
curl -s -X POST "${FORGEJO_URL}/api/v1/repos/dax/ansible_projects/branch_protections" \
  -H "Authorization: token ${FORGEJO_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "branch_name": "master",
    "enable_push": false,
    "enable_status_check": true,
    "status_check_contexts": [
      "Lint YAML",
      "Ansible lint",
      "Checkov IaC scan",
      "Scan for secrets",
      "ShellCheck",
      "Ruff Python lint"
    ],
    "required_approvals": 0
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('Branch protection:', d.get('branch_name', d))"
```

Expected: `Branch protection: master`

---

### Task 9: Add GitHub branch ruleset bypass

Without this, Forgejo's push mirror token cannot push to master on GitHub.

- [ ] **Step 1: Go to** `https://github.com/KolinSmith/ansible_projects/settings/rules`

- [ ] **Step 2: Add bypass**

Edit existing ruleset (or create one targeting `master`):
- Bypass list → Add → **Role: Repository admin**
- Save

---

### Task 10: Merge PR and verify end-to-end mirror

- [ ] **Step 1: Merge the PR on Forgejo**

Click **Merge pull request** on `https://git.hiddenba.se/dax/ansible_projects/pulls`

- [ ] **Step 2: Verify GitHub receives the mirror**

Wait ~30s, then check `https://github.com/KolinSmith/ansible_projects/commits/master`.
The merge commit should appear. If not after 2 minutes:
- Go to `https://git.hiddenba.se/dax/ansible_projects/settings` → Mirror settings → **Synchronize now**

- [ ] **Step 3: Verify local push remote**

```bash
git remote -v
# origin push should be: ssh://git@100.86.4.29:222/dax/ansible_projects.git
```

---

## Known Plan Gaps (for future repo migrations)

These were discovered during ansible_projects migration and are already fixed in the script:

1. **Token scopes** — Plan originally said "Issues: Read/Write, Repository: Read/Write" — WRONG. Correct scopes: `write:user` (repo creation) + `write:repository` (mirrors, branch protection). The script now gives a clear error with regeneration instructions if scope is missing.

2. **Pull mirror conversion** — All repos except docker_projects and dotfiles are pull mirrors on Forgejo. The script now detects `mirror: true` and converts by delete+recreate. It probes token scope BEFORE deleting to prevent leaving repos in a deleted state.

3. **Script idempotency** — Script is now safe to re-run at any stage: skips repo creation if already primary, skips push mirror if already configured.

4. **Repo visibility** — Pull mirror repos on Forgejo were public. The script creates replacement repos as private. Verify visibility after creation if needed.
