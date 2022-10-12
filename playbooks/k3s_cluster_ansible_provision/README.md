# Build a Kubernetes cluster using k3s via Ansible
forked from [k3s-io/k3s-ansible](https://github.com/k3s-io/k3s-ansible)

Author: <https://github.com/itwars>

## K3s Ansible Playbook

Build a Kubernetes cluster using Ansible with k3s. The goal is easily install a Kubernetes cluster (including a mysql database & haproxy loadbalancer) on machines running:

- [X] Debian
- [X] Ubuntu
- [X] CentOS

on processor architecture:

- [X] x64
- [X] arm64
- [X] armhf

## System requirements

Deployment environment must have Ansible 2.4.0+
Master and nodes must have passwordless SSH access

## Usage

First create a new directory based on the `sample` directory within the `inventory` directory:

```bash
cp -R inventory/sample inventory/my-cluster
```

Second, edit `inventory/my-cluster/hosts.ini` to match the system information gathered above (or create your own hosts file like "k3s_hosts"). For example:

```bash
[server_nodes]
192.16.35.12

[agent_nodes]
192.16.35.[10:11]

[k3s_cluster:children]
server_nodes
agent_nodes

[mysql_servers]
k3s-mysql-1 ansible_host=192.168.9.147

[load_balancers]
k3s-haproxy-1 ansible_host=192.168.9.148

```

If needed, you can also edit `inventory/my-cluster/group_vars/all.yml` to match your environment.

Start provisioning of the cluster using the following command:

```bash
ansible-playbook site.yml -i ~/code_base/ansible_projects/k3s_hosts
```

## Kubeconfig

To get access to your **Kubernetes** cluster just

```bash
scp debian@master_ip:~/.kube/config ~/.kube/config
```
