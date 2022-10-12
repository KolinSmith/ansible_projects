#!/usr/bin/python3
from meraki_sdk.meraki_sdk_client import MerakiSdkClient
import json
from pprint import pprint

token = '6bec40cf957de430a6f1f2baa056b99a4fac9ea0'
meraki = MerakiSdkClient(token)

orgs = meraki.organizations.get_organizations()

for org in orgs:
    if org ['name'] == 'DevNet Sandbox':
        orgId = org['id']

# pprint(orgId)

#create open dictionary called params
params={}
#for the key of organization_id we'll set that to orgId
params['organization_id'] = orgId
networks = meraki.networks.get_organization_networks(params)
# pprint(networks)

#get list of vlans from specified networks
for network in networks:
    if network['name'] == 'DevNet Sandbox ALWAYS ON':
        netId = network['id']

vlans = meraki.vlans.get_network_vlans(netId)
pprint(vlans)
