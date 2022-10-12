#!/usr/bin/python3

import gemini
import json

public_key = "account-COlk5KHAN8flBuZbdERc"
private_key = "4DiqsE8F4uSBcRJYWtsd7hZZCjEt"
symbol = "GUSDUSD"

#This function converts all your GUSD to USD
#(For Automating Deposits)
def _convertGUSDtoUSD(pub_key, priv_key):
    gusd_balance = 0

    trader = gemini.PrivateClient(pub_key, priv_key)
    if(list((type['available'] for type in  trader.get_balance() if type['currency'] == 'GUSD'))):
        gusd_balance = str(list((type['available'] for type in  trader.get_balance() if type['currency'] == 'GUSD'))[0])
    #use "buy" to convert USD to GUSD
    #use "sell" to convert GUSD into USD
    #replace gusd_balance below to transfer a static amount, use gusd_balance to transfer all your GUSD to USD
    results = trader.wrap_order(str(gusd_balance), "sell", str(symbol))
    print(results)


# def lambda_handler(event, context):
_convertGUSDtoUSD(public_key, private_key)
    # return {
    #     'statusCode': 200,
    #     'body': json.dumps('End of script')
    # }
