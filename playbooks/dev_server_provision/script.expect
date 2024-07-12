#!/usr/bin/expect
#this is to get around the default armbian but doesnt seem to compile for orange pi 3B

set target_host [lindex $argv 0]
set root_password "1234"
set ansible_playbook [lindex $argv 1]

spawn sshpass -p $root_password ssh root@$target_host
expect "password:"
send "$root_password\r"
expect "$ "
send "ansible-playbook $ansible_playbook\r"
expect eof
