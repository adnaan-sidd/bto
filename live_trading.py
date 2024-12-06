import MetaTrader5 as mt5
from strategy import TradingStrategy
from indicators import calculate_rsi
import yaml

# Load config
with open("config.yaml", "r") as file:
    config = yaml.safe_load(file)

# Initialize MT5
if not mt5.initialize(login=config['mt5_connection']['login'],
                      password=config['mt5_connection']['password'],
                      server=config['mt5_connection']['server']):
    print("MT5 Initialization failed")
    exit()

# Fetch live data
symbol = config['trading_parameters']['symbol']
rates = mt5.copy_rates_from_pos(symbol, mt5.TIMEFRAME_M15, 0, 100)
data = pd.DataFrame(rates)
data['time'] = pd.to_datetime(data['time'], unit='s')

# Calculate RSI
data['rsi'] = calculate_rsi(data, config['trading_parameters']['rsi_period'])

# Initialize strategy
strategy = TradingStrategy(config['trading_parameters'])

# Evaluate live data
for i in range(len(data)):
    row = data.iloc[i]
    rsi = row['rsi']
    decision, sl, tp = strategy.evaluate(row, rsi)

    if decision:
        # Place trade
        request = {
            "action": mt5.TRADE_ACTION_DEAL,
            "symbol": symbol,
            "volume": strategy.current_lot,
            "type": mt5.ORDER_TYPE_BUY if decision == "buy" else mt5.ORDER_TYPE_SELL,
            "price": row['close'],
            "sl": sl,
            "tp": tp,
            "deviation": 10
        }
        result = mt5.order_send(request)
        print(f"Trade sent: {result}")

mt5.shutdown()
