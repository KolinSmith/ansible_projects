#!/usr/bin/python3
import json
import gemini

public_key = ""  
private_key = ""
symbol = "ETHUSD"
tick_size = 6
quote_currency_price_increment = 2
#update symbol based on what crypto/fiat pair you want to buy. Default is BTCUSD, change to BTCEUR for Euros or ETHUSD for Ethereum (for example) - see all possibilities down in symbols and minimums link
#update tick_size and quote_currency_price_increment based on what crypto-pair you are buying. BTC is 8 - in the doc it says 1e-8 you want the number after e-. Or in the case of .01 you want 2 (because .01 is 1e-2) 
#Check out the API link below to see what you need for your pair
#https://docs.gemini.com/rest-api/#symbols-and-minimums

def _buyEtherium(buy_size,pub_key, priv_key):
    # Set up a buy for the current price
    trader = gemini.PrivateClient(pub_key, priv_key)
    factor = 0.999
    #to set a limit order at a fixed price (ie. $55,525) set execution_price = "55525.00" or execution_price = str(55525.00)
    price = str(round(float(trader.get_ticker(symbol)['ask'])*factor,quote_currency_price_increment))

    #most precise rounding + *.999 for fee inclusion
    eth_amount = round((buy_size*factor)/float(price),tick_size)

    #execute maker buy, round to 8 decimal places for precision, multiply price by 2 so your limit order always gets fully filled
    buy = trader.new_order(symbol, str(eth_amount), price, "buy", ["maker-or-cancel"])
    print(f'Maker Buy: {buy}')

#should buy $50 of eth when script is run
#def lambda_handler(event, context):
_buyEtherium(50, public_key, private_key)
#    return {
#        'statusCode': 200,
#        'body': json.dumps('End of script')
#    }
