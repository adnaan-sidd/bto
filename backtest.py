import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from indicators import calculate_rsi
from strategy import TradingStrategy
import yaml
from datetime import datetime

# Load configuration from YAML file
with open("config.yaml", "r") as file:
    config = yaml.safe_load(file)

# Load historical data
data = pd.read_csv(config['backtest_parameters']['data_path'], parse_dates=['time'])
data.set_index('time', inplace=True)

# Calculate RSI
data['rsi'] = calculate_rsi(data, config['trading_parameters']['rsi_period'])

# Initialize strategy
strategy = TradingStrategy(config['trading_parameters'])

# Initialize lists for storing trade information
trades = []
profits = []

# Backtesting loop
for i in range(len(data)):
    row = data.iloc[i]
    rsi = row['rsi']
    decision, sl, tp = strategy.evaluate(row, rsi)

    if decision:
        # Log trade information
        trade = {
            'time': row.name,
            'open': row['close'],
            'type': decision,
            'sl': sl,
            'tp': tp,
        }
        trades.append(trade)

        # Simulate trade outcome (closing the trade at the next available price)
        for j in range(i + 1, len(data)):
            if (decision == 'buy' and data.iloc[j]['close'] >= tp) or (decision == 'sell' and data.iloc[j]['close'] <= tp):
                # Take profit hit
                profit = tp - row['close'] if decision == 'buy' else row['close'] - tp
                profits.append(profit)
                break
            elif (decision == 'buy' and data.iloc[j]['close'] <= sl) or (decision == 'sell' and data.iloc[j]['close'] >= sl):
                # Stop loss hit
                profit = sl - row['close'] if decision == 'buy' else row['close'] - sl
                profits.append(profit)
                break
        else:
            # If exit condition not hit, assume trade closed at end of data
            profits.append(data.iloc[-1]['close'] - row['close'] if decision == 'buy' else row['close'] - data.iloc[-1]['close'])

# Summarizing results
total_profit = np.sum(profits)
total_trades = len(trades)
print(f"Total Trade Profit: {total_profit:.2f}")
print(f"Total Trades: {total_trades}")

# Plotting the results
plt.figure(figsize=(14, 7))
plt.plot(data['close'], label='Close Price', alpha=0.5)

# Plot trade entries and exits
for trade in trades:
    plt.scatter(trade['time'], trade['open'], color='green' if trade['type'] == 'buy' else 'red', label='Buy' if trade['type'] == 'buy' else 'Sell', marker='^' if trade['type'] == 'buy' else 'v', s=100)

plt.title('Backtesting Results')
plt.xlabel('Time')
plt.ylabel('Price')
plt.legend()
plt.grid()
plt.show()