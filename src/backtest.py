import pandas as pd
from fetch_data import fetch_data
from calculate_rsi import calculate_rsi
from trading_logic import trading_logic

def backtest(symbol='EURUSD=X', period='1mo', interval='15m'):
    data = fetch_data(symbol, period, interval)
    data = calculate_rsi(data)
    trades = trading_logic(data)
    
    # Analyze results
    wins = [trade for trade in trades if trade['type'] == 'buy' and trade['price'] + 30 <= trade['price']]
    losses = [trade for trade in trades if trade['type'] == 'buy' and trade['price'] - 10 >= trade['price']]
    win_rate = len(wins) / len(trades) if trades else 0
    print(f"Total Trades: {len(trades)}, Wins: {len(wins)}, Losses: {len(losses)}, Win Rate: {win_rate:.2f}")

if __name__ == "__main__":
    backtest()