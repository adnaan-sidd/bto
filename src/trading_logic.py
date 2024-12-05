import pandas as pd
import matplotlib.pyplot as plt

def trading_logic(data, lot_size=0.10, multiplier=1.7, max_loss_streak=7, sl=10, tp=30, trailing_stop=5):
    loss_streak = 0
    current_lot_size = lot_size
    trades = []

    for i in range(len(data) - 1):  # Ensure we don't go out of bounds
        if data['RSI'][i] <= 35:
            entry_price = data['close'][i]
            trades.append({'type': 'buy', 'price': entry_price, 'lot_size': current_lot_size, 'time': data['time'][i]})
            for j in range(i + 1, len(data)):
                if data['close'][j] >= entry_price + tp:
                    loss_streak = 0
                    current_lot_size = lot_size
                    break
                elif data['close'][j] <= entry_price - sl:
                    loss_streak += 1
                    if loss_streak >= max_loss_streak:
                        loss_streak = 0
                        current_lot_size = lot_size
                        return trades  # Stop the bot
                    else:
                        current_lot_size *= multiplier
                    break
                elif data['close'][j] <= entry_price + trailing_stop:
                    entry_price = data['close'][j]

        elif data['RSI'][i] >= 70:
            entry_price = data['close'][i]
            trades.append({'type': 'sell', 'price': entry_price, 'lot_size': current_lot_size, 'time': data['time'][i]})
            for j in range(i + 1, len(data)):
                if data['close'][j] <= entry_price - tp:
                    loss_streak = 0
                    current_lot_size = lot_size
                    break
                elif data['close'][j] >= entry_price + sl:
                    loss_streak += 1
                    if loss_streak >= max_loss_streak:
                        loss_streak = 0
                        current_lot_size = lot_size
                        return trades  # Stop the bot
                    else:
                        current_lot_size *= multiplier
                    break
                elif data['close'][j] >= entry_price - trailing_stop:
                    entry_price = data['close'][j]

    return trades

def visualize_trades(data, trades):
    plt.figure(figsize=(14, 7))
    plt.plot(data['time'], data['close'], label='Close Price')
    
    buy_trades = [trade for trade in trades if trade['type'] == 'buy']
    sell_trades = [trade for trade in trades if trade['type'] == 'sell']
    
    plt.scatter([trade['time'] for trade in buy_trades], [trade['price'] for trade in buy_trades], marker='^', color='g', label='Buy')
    plt.scatter([trade['time'] for trade in sell_trades], [trade['price'] for trade in sell_trades], marker='v', color='r', label='Sell')
    
    plt.xlabel('Time')
    plt.ylabel('Price')
    plt.title('Trading Strategy Visualization')
    plt.legend()
    plt.show()

def save_trades_to_excel(trades, filename='trades.xlsx'):
    df = pd.DataFrame(trades)
    df.to_excel(filename, index=False)

if __name__ == "__main__":
    # Example usage with sample data
    try:
        data = pd.read_csv('data/yahoo_historical_data.csv')
    except FileNotFoundError:
        print("File not found. Please ensure the file exists and try again.")
        exit()
    
    # Check for alternative column names and rename to 'time'
    if 'date' in data.columns:
        data.rename(columns={'date': 'time'}, inplace=True)
    elif 'timestamp' in data.columns:
        data.rename(columns={'timestamp': 'time'}, inplace=True)
    
    # Ensure the 'time' column is in datetime format
    if 'time' not in data.columns:
        print("The required 'time' column is missing from the dataset.")
        exit()
    
    data['time'] = pd.to_datetime(data['time'])
    
    trades = trading_logic(data)
    
    visualize_trades(data, trades)
    
    save_trades_to_excel(trades)