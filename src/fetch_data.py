import os
import pandas as pd
from yahooquery import Ticker
import MetaTrader5 as mt5

# Fetch historical data using yahooquery
def fetch_yahoo_data(symbol, period='4mo', interval='15m'):
    ticker = Ticker(symbol)
    data = ticker.history(period=period, interval=interval)
    data.reset_index(inplace=True)
    
    # Create 'data' directory if it doesn't exist
    if not os.path.exists('data'):
        os.makedirs('data')
    
    # Save data to 'data' directory
    data.to_csv('data/yahoo_historical_data.csv', index=False)
    return data

# Fetch historical data from MT5 with 1-hour timeframe
def fetch_mt5_data(symbol, timeframe=mt5.TIMEFRAME_H1, num_candles=10000):
    if not mt5.initialize():
        print("initialize() failed")
        mt5.shutdown()
        return None

    rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, num_candles)
    mt5.shutdown()
    
    data = pd.DataFrame(rates)
    data['time'] = pd.to_datetime(data['time'], unit='s')
    
    # Create 'data' directory if it doesn't exist
    if not os.path.exists('data'):
        os.makedirs('data')
    
    # Save data to 'data' directory
    data.to_csv('data/mt5_historical_data.csv', index=False)
    return data

if __name__ == "__main__":
    fetch_yahoo_data('EURUSD=X')
    fetch_mt5_data('EURUSD')