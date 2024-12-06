import pandas as pd
from ta.momentum import RSIIndicator

def calculate_rsi(data: pd.DataFrame, period: int) -> pd.Series:
    """
    Calculate the RSI for the given data.
    """
    rsi = RSIIndicator(data['close'], window=period).rsi()
    return rsi
