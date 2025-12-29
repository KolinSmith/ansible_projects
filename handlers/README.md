# Global Ansible Handlers

Common handlers that can be imported into any playbook or role.

## Reboot Handlers

### Usage in Playbooks

```yaml
---
- name: My Playbook
  hosts: all
  become: true
  handlers:
    - import_tasks: ../../handlers/reboot.yml

  tasks:
    - name: Update kernel
      apt:
        name: linux-generic
        state: latest
      notify: reboot
```

### Usage in Roles

```yaml
# In your role's tasks/main.yml
- name: Install updates
  apt:
    upgrade: dist
  notify: reboot

# In your role's handlers/main.yml
- import_tasks: ../../../handlers/reboot.yml
```

### Available Handlers

- **`reboot`** - Standard reboot with 30s post-reboot delay
  ```yaml
  notify: reboot
  ```

- **`reboot now`** - Immediate reboot with minimal 10s post-reboot delay
  ```yaml
  notify: reboot now
  ```

- **`reboot delayed`** - Reboot after 60s delay (good for giving users warning)
  ```yaml
  notify: reboot delayed
  ```

## Adding More Global Handlers

Create new handler files in this directory and import them the same way.
