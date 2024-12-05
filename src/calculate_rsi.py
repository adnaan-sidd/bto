import pandas as pd
import ta

def calculate_rsi(data, period=14):
    data['RSI'] = ta.momentum.RSIIndicator(data['close'], window=period).rsi()
    return data

if __name__ == "__main__":
    yahoo_data = pd.read_csv('data/yahoo_historical_data.csv')
    yahoo_data = calculate_rsi(yahoo_data)
    yahoo_data.to_csv('data/yahoo_historical_data.csv', index=False)

    mt5_data = pd.read_csv('data/mt5_historical_data.csv')
    mt5_data = calculate_rsi(mt5_data)
    mt5_data.to_csv('data/mt5_historical_data.csv', index=False)