//+------------------------------------------------------------------+
//|                    EURUSD RSI Strategy - 15 Minute Chart         |
//+------------------------------------------------------------------+
#property strict

// Strategy Configuration
input string StrategyName = "EURUSD_RSI_Strategy";
input string Symbol = "EURUSD";           // Trading Symbol
input ENUM_TIMEFRAMES ChartTimeframe = PERIOD_M15; // 15-Minute Timeframe

// Trading Parameters
input double initialLotSize = 0.10;       // Initial Lot Size
input int tpPips = 30;                    // Take Profit in Pips
input int slPips = 10;                    // Stop Loss in Pips
input int rsiPeriod = 14;                 // RSI Period
input double rsiBuyThreshold = 35.0;      // Buy Threshold
input double rsiSellThreshold = 70.0;     // Sell Threshold

// Risk Management
input int maxLossStreak = 7;              // Max Stop Loss Hit Streak
input double lotMultiplier = 1.7;         // Lot Size Multiplier on Losing Streak
input double trailingStopDistance = 10.0; // Trailing Stop Distance in Pips

// Logging and Performance Tracking
input bool enableLogging = true;          // Enable Detailed Logging
input string logFilePath = "EURUSD_RSI_Strategy_Log.csv";

// Global Variables
double currentLotSize;
int lossStreak;
int dailyWins;
int dailyLosses;
datetime lastTradeTime;
datetime currentDay;
double dailyProfit;
double totalProfit;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Reset all trading parameters
    ResetTradingParameters();
    
    // Open log file if logging is enabled
    if(enableLogging)
    {
        int logFile = FileOpen(logFilePath, FILE_WRITE | FILE_CSV, ',');
        if(logFile != INVALID_HANDLE)
        {
            FileWrite(logFile, "Time", "Event", "Details", "Lot Size", "Daily Wins", "Daily Losses", "Loss Streak");
            FileClose(logFile);
        }
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Logging Function                                                 |
//+------------------------------------------------------------------+
void LogEvent(string event, string details)
{
    if(!enableLogging) return;
    
    int logFile = FileOpen(logFilePath, FILE_READ | FILE_WRITE | FILE_CSV, ',');
    if(logFile != INVALID_HANDLE)
    {
        FileSeek(logFile, 0, SEEK_END);
        FileWrite(logFile, 
            TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS), 
            event, 
            details, 
            DoubleToString(currentLotSize, 2),
            IntegerToString(dailyWins),
            IntegerToString(dailyLosses),
            IntegerToString(lossStreak)
        );
        FileClose(logFile);
    }
}

//+------------------------------------------------------------------+
//| Reset Trading Parameters                                         |
//+------------------------------------------------------------------+
void ResetTradingParameters()
{
    currentLotSize = initialLotSize;
    lossStreak = 0;
    dailyWins = 0;
    dailyLosses = 0;
    dailyProfit = 0;
    totalProfit = 0;
    currentDay = TimeCurrent();
    
    LogEvent("RESET", "Trading parameters reset to initial state");
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check if we're on a new day
    if(TimeCurrent() - currentDay >= 86400) // 24 hours
    {
        ResetTradingParameters();
    }

    // Only trade on EURUSD 15-minute chart
    if(Symbol() != Symbol || Period() != ChartTimeframe) return;

    // RSI calculation
    double rsi = iRSI(Symbol(), ChartTimeframe, rsiPeriod, PRICE_CLOSE);

    // Check for open positions
    if (!PositionSelect(Symbol()))
    {
        double askPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
        double bidPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);

        // Buy Condition: RSI <= 35
        if (rsi <= rsiBuyThreshold)
        {
            double takeProfitPrice = askPrice + (tpPips * _Point);
            double stopLossPrice = askPrice - (slPips * _Point);

            if (ExecuteOrder(ORDER_TYPE_BUY, askPrice, currentLotSize, takeProfitPrice, stopLossPrice))
            {
                LogEvent("BUY_ORDER", "RSI Buy Order Placed");
            }
        }
        // Sell Condition: RSI >= 70
        else if (rsi >= rsiSellThreshold)
        {
            double takeProfitPrice = bidPrice - (tpPips * _Point);
            double stopLossPrice = bidPrice + (slPips * _Point);

            if (ExecuteOrder(ORDER_TYPE_SELL, bidPrice, currentLotSize, takeProfitPrice, stopLossPrice))
            {
                LogEvent("SELL_ORDER", "RSI Sell Order Placed");
            }
        }
    }

    // Manage existing positions
    ManageOpenPositions();
}

//+------------------------------------------------------------------+
//| Execute Order Function                                           |
//+------------------------------------------------------------------+
bool ExecuteOrder(int orderType, double price, double volume, double takeProfit, double stopLoss)
{
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = volume;
    request.type = orderType;
    request.price = price;
    request.tp = takeProfit;
    request.sl = stopLoss;
    request.deviation = 10;
    request.magic = 0;
    request.comment = (orderType == ORDER_TYPE_BUY ? "RSI Buy" : "RSI Sell");

    return OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
    if (PositionSelect(Symbol()))
    {
        double profit = PositionGetDouble(POSITION_PROFIT);
        double currentStopLoss = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        // Trailing Stop Loss
        if (profit > 0)
        {
            double newTrailingStop;
            if (posType == POSITION_TYPE_BUY)
            {
                newTrailingStop = SymbolInfoDouble(Symbol(), SYMBOL_BID) - (trailingStopDistance * _Point);
                if (newTrailingStop > currentStopLoss)
                    PositionModify(newTrailingStop, 0);
            }
            else if (posType == POSITION_TYPE_SELL)
            {
                newTrailingStop = SymbolInfoDouble(Symbol(), SYMBOL_ASK) + (trailingStopDistance * _Point);
                if (newTrailingStop < currentStopLoss)
                    PositionModify(newTrailingStop, 0);
            }
        }

        // Take Profit Hit
        if (profit >= (tpPips * _Point))
        {
            dailyWins++;
            dailyProfit += profit;
            totalProfit += profit;
            
            LogEvent("TP_HIT", "Take Profit Reached - Resetting Parameters");
            
            ClosePosition();
            ResetTradingParameters();
        }
        // Stop Loss Hit
        else if (profit <= -(slPips * _Point))
        {
            lossStreak++;
            dailyLosses++;
            
            // Multiply lot size
            currentLotSize *= lotMultiplier;
            
            LogEvent("SL_HIT", "Stop Loss Reached - Increasing Lot Size");
            
            ClosePosition();
            
            // Check if max loss streak is reached
            if (lossStreak >= maxLossStreak)
            {
                LogEvent("MAX_LOSS_STREAK", "Maximum Loss Streak Reached - Stopping Strategy");
                ExpertRemove(); // Stop the Expert Advisor
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Modify Position                                                  |
//+------------------------------------------------------------------+
void PositionModify(double newStopLoss, double newTakeProfit)
{
    if(!PositionSelect(Symbol())) return;

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action = TRADE_ACTION_SLTP;
    request.symbol = Symbol();
    request.sl = newStopLoss;
    request.tp = newTakeProfit;
    request.volume = PositionGetDouble(POSITION_VOLUME);

    OrderSend(request, result);
}

//+------------------------------------------------------------------+
//| Close Position                                                   |
//+------------------------------------------------------------------+
void ClosePosition()
{
    if(!PositionSelect(Symbol())) return;

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);

    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = volume;
    request.type = (posType == POSITION_TYPE_BUY ? ORDER_TYPE_SELL : ORDER_TYPE_BUY);
    request.price = (request.type == ORDER_TYPE_SELL ? SymbolInfoDouble(Symbol(), SYMBOL_BID) : SymbolInfoDouble(Symbol(), SYMBOL_ASK));
    request.deviation = 10;

    OrderSend(request, result);
}