#!/usr/bin/python3
import requests
import json

###### LOGIN ######
url = "https://sandboxapicdc.cisco.com:443/api/aaaLogin.json"

payload = {
    "aaaUser": {
        "attributes": {
            "name": "admin",
            "pwd": "!v3G@!4@Y"
        }
    }
}
headers = {
    'Content-Type': "application/json"
}

response = requests.post(url, data=json.dumps(payload), headers=headers, verify=False).json()
# json.dumps converts the data to json
# verify equals false because this is using a self signed cert
# the .json specifies that the response will be a json, so convert it from json to python and store the python result in the response variable

# print(json.dumps(response, indent=2, sort_keys=True))

# PARSE TOKEN AND SET COOKIE
token = response['imdata'][0]['aaaLogin']['attributes']['token']
#create an open dictionary called "cookie"
cookie = {}
cookie['APIC-cookie'] = token
# in order to move on and continue making requets with that token we have to specify a cookie
# the cookie has to be a dictionary object

###### GET APN ######
# GET APPLICATION PROFILE
url = "https://sandboxapicdc.cisco.com:443/api/node/mo/uni/tn-Heroes/ap-Save_The_Planet.json"

headers = {
    'cache-control': "no-cache"
}

get_response = requests.get(
    url, headers=headers, cookies=cookie, verify=False).json()

# print(json.dumps(get_response, indent=2, sort_keys=True))

##### UPDATE APN DESCRIPTION ######
# SET DESCRIPTION
post_payload = {
    "fvAp": {
        "attributes": {
            "descr": "",
            "dn": "uni/tn-Heroes/ap-Save_The_Planet"
        }
    }
}
#push the data (set the new description if you added one)
post_response = requests.post(
    url, headers=headers, cookies=cookie, verify=False, data=json.dumps(post_payload)).json()

#get the data (check to make sure the description actually changed)
get_response = requests.get(
    url, headers=headers, cookies=cookie, verify=False).json()

print(json.dumps(get_response, indent=2, sort_keys=True))
