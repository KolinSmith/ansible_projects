to run:
sudo ansible-playbook -i <ip of new server with username and password setup>, /home/dax/code_base/ansible_projects/playbooks/proxmoxServerProvision/proxmoxServerProvision.yml -e ansible_python_interpreter=/usr/bin/python --ask-pass --user serveradmin -K

***
keep "," on the end of the ip for it to work

might need to specify the python interpreter either python, python2.7, python3, etc

keep in mind that you need to change the hosts in the main file and bootstrap_python file to target "all" if you wanna target not in the hosts file
***

can also run as:
sudo ansible-playbook /home/dax/code_base/ansible_projects/proxmoxServerProvision/proxmoxServerProvision.yml -i /home/dax/code_base/ansible_projects/hosts --vault-pass /home/dax/code_base/dotfiles/.ansible_password

or like:
sudo ansible-playbook /home/dax/code_base/ansible_projects/playbooks/proxmoxServerProvision/proxmoxServerProvision.yml


This playbook setups a proxmox vm for me after I have cloned it from a template. It installs packages I want, setups firewall rules, updates the server, creates a user and gives it an ssh key, and more.
