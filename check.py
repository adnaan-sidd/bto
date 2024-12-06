import MetaTrader5 as mt5

if mt5.initialize():
    print("MetaTrader5 initialized successfully!")
    mt5.shutdown()
else:
    print(f"Failed to initialize MetaTrader5. Error code: {mt5.last_error()}")
