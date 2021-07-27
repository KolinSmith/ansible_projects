to run:
sudo ansible-playbook -i <ip of new server with username and password setup>, /home/dax/code_base/ansible_projects/proxmoxServerProvision/proxmoxServerProvision.yml --ask-pass --user serveradmin -K

can also run as:
sudo ansible-playbook /home/dax/code_base/ansible_projects/proxmoxServerProvision/proxmoxServerProvision.yml -i /home/dax/code_base/ansible_projects/hosts --vault-pass /home/dax/code_base/dotfiles/.ansible_password
