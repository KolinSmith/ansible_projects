Orange Pi Disable Ramlog Role
This Ansible role disables the Armbian ramlog system on Orange Pi devices and configures direct disk logging with optimizations for SD card longevity.

Requirements
Target system must be running Armbian
Ansible 2.9 or higher
Role Variables
Available variables are listed below, along with default values (see defaults/main.yml):

yaml
# Whether to enable aggressive log rotation
orangepi_aggressive_rotation: true

# Log rotation settings
orangepi_log_rotation_days: 3
orangepi_atop_retention_days: 2
orangepi_sysstat_retention_days: 2

# Rsyslog optimization settings
orangepi_disable_file_sync: true
orangepi_reduce_repeated_messages: true
Dependencies
None.

Example Playbook
yaml
- hosts: orangepi_devices
  become: yes
  roles:
    - orangepi_disable_ramlog
Or with custom variables:

yaml
- hosts: orangepi_devices
  become: yes
  roles:
    - role: orangepi_disable_ramlog
      vars:
        orangepi_log_rotation_days: 5
        orangepi_atop_retention_days: 3
What This Role Does
Stops and disables the armbian-ramlog service
Safely migrates existing logs from zram to disk storage
Unmounts zram and bind mounts used by ramlog
Configures rsyslog for optimized direct disk logging
Sets up aggressive log rotation to minimize storage usage
Disables zram logging configuration
Cleans up zram devices
Benefits
Eliminates crashes caused by full ramlog storage
Provides unlimited log storage (limited only by disk space)
Optimizes rsyslog for SD card longevity
Implements aggressive log rotation to control storage usage
File Structure
orangepi_disable_ramlog/
├── defaults/
│   └── main.yml          # Default variables
├── meta/
│   └── main.yml          # Role metadata
├── tasks/
│   └── main.yml          # Main task list
├── templates/
│   └── orangepi-aggressive.j2  # Log rotation template
├── vars/
│   └── main.yml          # Role variables
└── README.md             # This file
License
GPL-2.0-or-later

Author Information
Created to solve Orange Pi stability issues caused by full ramlog storage.

