#!/usr/bin/python3
import json
import gemini

public_key = "account-COlk5KHAN8flBuZbdERc"
private_key = "4DiqsE8F4uSBcRJYWtsd7hZZCjEt"
trader = gemini.PrivateClient(public_key, private_key)

#withdraws full available balance of specified coin to given address
def _withdrawFullCoinBalance(coin, address):
    amount = "0"
    for currency in trader.get_balance():
        if(currency['currency'] == coin):
            amount = currency['availableForWithdrawal']
            print(f'Amount Available for Withdrawal: {amount}')

    #Replace the amount variable below with ".001" to withdraw .001 BTC - change the amount if you want to withdraw some static amount
    withdraw = trader.withdraw_to_address(coin, address, amount)
    print(withdraw)

# def lambda_handler(event, context):
#Add addresses below
#MAKE SURE THAT YOUR WALLET ADDRESS IS FOR THE SAME TOKEN AS THE WITHDRAWAL SYMBOL OR YOU COULD LOSE FUNDS
#(ie. in _withdrawPartialCoinBalance(bitcoin_withdrawal_symbol, btc_address, .75) both btc_address and bitcoin_withdrawal_symbol reference the same coin (BTC))

bitcoin_withdrawal_symbol = "BTC"
ethereum_withdrawal_symbol = "ETH"
btc_address = 'bc1q8l22n0f4nrn2dkhrv7qj4hmgfah2pt04pauug0'
eth_address = '0x2E24C5f4E013183798bb229F6D925Ea74A33E20F'
# _withdrawFullCoinBalance(bitcoin_withdrawal_symbol, btc_address)
_withdrawFullCoinBalance(ethereum_withdrawal_symbol, eth_address)

    # return {
    #     'statusCode': 200,
    #     'body': json.dumps('Hello from Lambda!')
    # }
