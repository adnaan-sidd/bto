import os
import pandas as pd
import ta
import MetaTrader5 as mt5
import time
from fetch_data import fetch_yahoo_data, fetch_mt5_data
from calculate_rsi import calculate_rsi
from trading_logic import trading_logic

# Connect to MT5 and place orders
def connect_mt5():
    if not mt5.initialize():
        print("initialize() failed")
        mt5.shutdown()
        return False
    return True

def place_order(symbol, order_type, lot_size, sl, tp):
    price = mt5.symbol_info_tick(symbol).ask if order_type == 'buy' else mt5.symbol_info_tick(symbol).bid
    deviation = 20
    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": symbol,
        "volume": lot_size,
        "type": mt5.ORDER_TYPE_BUY if order_type == 'buy' else mt5.ORDER_TYPE_SELL,
        "price": price,
        "sl": price - sl * mt5.symbol_info(symbol).point if order_type == 'buy' else price + sl * mt5.symbol_info(symbol).point,
        "tp": price + tp * mt5.symbol_info(symbol).point if order_type == 'buy' else price - tp * mt5.symbol_info(symbol).point,
        "deviation": deviation,
        "magic": 234000,
        "comment": "python script open",
        "type_time": mt5.ORDER_TIME_GTC,
        "type_filling": mt5.ORDER_FILLING_IOC,
    }
    result = mt5.order_send(request)
    return result

# Main function to monitor the market and execute trades based on the strategy
def main():
    symbol = 'EURUSD'
    
    while True:
        # Fetch latest market data from MT5 and Yahoo Finance separately and save to different files.
        fetch_yahoo_data('EURUSD=X')
        fetch_mt5_data(symbol)
        
        # Calculate RSI on the fetched Yahoo Finance data.
        yahoo_data = pd.read_csv('data/yahoo_historical_data.csv')
        yahoo_data = calculate_rsi(yahoo_data)
        yahoo_data.to_csv('data/yahoo_historical_data.csv', index=False)

        # Calculate RSI on the fetched MT5 data.
        mt5_data = pd.read_csv('data/mt5_historical_data.csv')
        mt5_data = calculate_rsi(mt5_data)
        mt5_data.to_csv('data/mt5_historical_data.csv', index=False)

        # Apply trading logic to find trade opportunities based on Yahoo Finance data.
        trades_yahoo = trading_logic(yahoo_data)

        # Apply trading logic to find trade opportunities based on MT5 data.
        trades_mt5 = trading_logic(mt5_data)

        # Connect to MT5 and place orders based on the trading logic for Yahoo Finance data.
        if connect_mt5():
            for trade in trades_yahoo:
                result = place_order(symbol, trade['type'], trade['lot_size'], 10, 30)
                print(result)
            for trade in trades_mt5:
                result = place_order(symbol, trade['type'], trade['lot_size'], 10, 30)
                print(result)
            mt5.shutdown()
        
        # Wait for a specified interval before checking the market again (e.g., 15 minutes)
        time.sleep(900)

if __name__ == "__main__":
    main()