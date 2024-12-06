import MetaTrader5 as mt5
import pandas as pd
import os
from datetime import datetime, timedelta

# Initialize MT5 connection
def initialize_mt5():
    if not mt5.initialize():
        print(f"MT5 initialization failed: {mt5.last_error()}")
        return False
    print("MT5 initialized successfully!")
    return True

# Fetch historical data
def fetch_data(symbol, timeframe, start_date, end_date, output_file):
    # Map timeframe strings to MT5 timeframes
    timeframe_map = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
    }

    if timeframe not in timeframe_map:
        print(f"Invalid timeframe: {timeframe}")
        return False

    # Convert datetime to UTC for MT5
    start_date_utc = start_date - timedelta(hours=3)  # MT5 requires UTC+0
    end_date_utc = end_date - timedelta(hours=3)

    # Request historical data
    rates = mt5.copy_rates_range(symbol, timeframe_map[timeframe], start_date_utc, end_date_utc)

    if rates is None or len(rates) == 0:
        print(f"Failed to fetch data for {symbol}. Error: {mt5.last_error()}")
        return False

    # Convert to DataFrame
    df = pd.DataFrame(rates)
    df['time'] = pd.to_datetime(df['time'], unit='s')  # Convert time to human-readable format
    df = df[['time', 'open', 'high', 'low', 'close', 'tick_volume']]  # Select useful columns

    # Save to CSV
    os.makedirs(os.path.dirname(output_file), exist_ok=True)
    df.to_csv(output_file, index=False)
    print(f"Data for {symbol} saved to {output_file}")
    return True

# Main function
def main():
    # Settings
    symbol = "EURUSD"  # Replace with other symbols as needed
    timeframe = "M15"  # Change to other timeframes like "M1", "H1", etc.
    start_date = datetime.now() - timedelta(days=120)  # Fetch last 4 months of data
    end_date = datetime.now()
    output_file = f"data/{symbol}_{timeframe}.csv"

    # Initialize MT5
    if not initialize_mt5():
        return

    # Fetch and save data
    fetch_data(symbol, timeframe, start_date, end_date, output_file)

    # Shutdown MT5
    mt5.shutdown()

if __name__ == "__main__":
    main()
