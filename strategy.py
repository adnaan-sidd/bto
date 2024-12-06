import pandas as pd

class TradingStrategy:
    def __init__(self, config):
        self.initial_lot = config['initial_lot']
        self.sl_pips = config['sl_pips']
        self.tp_pips = config['tp_pips']
        self.lot_multiplier = config['lot_multiplier']
        self.max_sl_streak = config['max_sl_streak']
        self.rsi_buy = config['rsi_buy']
        self.rsi_sell = config['rsi_sell']
        
        # State tracking
        self.current_lot = self.initial_lot
        self.sl_streak = 0

    def evaluate(self, row, rsi):
        """
        Evaluate buy/sell conditions based on RSI and update state.
        """
        decision = None
        sl = None  # Initialize Stop Loss
        tp = None  # Initialize Take Profit

        # Buy Condition
        if rsi <= self.rsi_buy:
            decision = "buy"
            sl = row['close'] - (self.sl_pips * 0.0001)  # Calculate SL for buy
            tp = row['close'] + (self.tp_pips * 0.0001)  # Calculate TP for buy
        
        # Sell Condition
        elif rsi >= self.rsi_sell:
            decision = "sell"
            sl = row['close'] + (self.sl_pips * 0.0001)  # Calculate SL for sell
            tp = row['close'] - (self.tp_pips * 0.0001)  # Calculate TP for sell

        # If no decision made, sl and tp remain None
        return decision, sl, tp