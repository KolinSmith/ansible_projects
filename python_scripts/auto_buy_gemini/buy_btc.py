#!/usr/bin/python3
import json
import gemini

public_key = "account-COlk5KHAN8flBuZbdERc"
private_key = "4DiqsE8F4uSBcRJYWtsd7hZZCjEt"
symbol = "BTCUSD"
tick_size = 8
quote_currency_price_increment = 2
#update symbol based on what crypto/fiat pair you want to buy. Default is BTCUSD, change to BTCEUR for Euros or ETHUSD for Ethereum (for example) - see all possibilities down in symbols and minimums link
#update tick_size and quote_currency_price_increment based on what crypto-pair you are buying. BTC is 8 - in the doc it says 1e-8 you want the number after e-. Or in the case of .01 you want 2 (because .01 is 1e-2)
#Check out the API link below to see what you need for your pair
#https://docs.gemini.com/rest-api/#symbols-and-minimums

def _buyBitcoin(buy_size,pub_key, priv_key):
    # Set up a buy for 0.999 times the current price add more decimals for a higher price and faster fill, if the price is too close to spot your order won't post.
    # Lower factor makes the order cheaper but fills quickly (0.5 would set an order for half the price and so your order could take months/years/never to fill)
    trader = gemini.PrivateClient(pub_key, priv_key)
    symbol_spot_price = float(trader.get_ticker(symbol)['ask'])
    print(symbol_spot_price)
    factor = 0.999
    #to set a limit order at a fixed price (ie. $55,525) set execution_price = "55525.00" or execution_price = str(55525.00)
    execution_price = str(round(symbol_spot_price*factor,quote_currency_price_increment))

    #set amount to the most precise rounding (tick_size) and multiply by 0.999 for fee inclusion - if you make an order for $20.00 there should be $19.98 coin bought and $0.02 (0.10% fee)
    amount = round((buy_size*.999)/float(execution_price),tick_size)

    #execute maker buy with the appropriate symbol, amount, and calculated price
    buy = trader.new_order(symbol, str(amount), execution_price, "buy", ["maker-or-cancel"])
    print(f'Maker Buy: {buy}')


#should buy $50 of btc when script is run
# def lambda_handler(event, context):
_buyBitcoin(50, public_key, private_key)
    # return {
    #     'statusCode': 200,
    #     'body': json.dumps('End of script')
    # }
