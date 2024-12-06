//+------------------------------------------------------------------+
//|                    EURUSD RSI Live Trading Strategy              |
//+------------------------------------------------------------------+
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

// Logging Function
void DebugLog(string message, bool isImportant = false) {
    string prefix = isImportant ? "CRITICAL: " : "";
    Print(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + prefix + message);
}

// Strategy Configuration
input string InpStrategyName = "EURUSD_RSI_Live_Strategy";
input string InpInputSymbol = "EURUSD"; // Trading Symbol
input ENUM_TIMEFRAMES InpChartTimeframe = PERIOD_M15; // 15-Minute Timeframe

// Trading Parameters
input double InpInitialVolume = 0.10; // Initial Volume (equivalent to Lot Size)
input int InpTakeProfitPips = 30; // Take Profit in Pips
input int InpStopLossPips = 10; // Stop Loss in Pips
input int InpRsiPeriod = 14; // RSI Period
input double InpRsiBuyThreshold = 30.0; // Buy Threshold
input double InpRsiSellThreshold = 70.0; // Sell Threshold

// Risk Management Inputs
input int InpMaxLossStreak = 7; // Max Stop Loss Hit Streak
input double InpVolumeMultiplier = 1.7; // Volume Multiplier on Losing Streak
input int InpDailyResetHour = 0; // Hour to reset daily trading (0-23)

// Global Strategy Class
class CRSILiveStrategy {
private:
    CTrade trade;
    CPositionInfo positionInfo;
    
    // Trading Parameters
    double currentVolume;
    int lossStreak;
    bool isTrading;
    int rsiHandle;
    datetime lastTradeTime;
    datetime lastDailyResetTime;

    // Performance tracking
    int totalTrades;
    int profitableTrades;
    int unprofitableTrades;
    double totalProfit;

    // Check if it's time for daily reset
    bool IsDailyResetTime() {
        datetime currentTime = TimeCurrent();
        datetime resetTime = StringToTime(TimeToString(currentTime, TIME_DATE) + 
                                          " " + IntegerToString(InpDailyResetHour) + ":00");
        
        // Check if we haven't reset today and it's reset time
        return (lastDailyResetTime == 0 || 
                currentTime >= resetTime && lastDailyResetTime < resetTime);
    }

    // Perform daily reset
    void DailyReset() {
        DebugLog("Performing Daily Reset", true);
        
        // Reset key trading parameters
        currentVolume = InpInitialVolume;
        lossStreak = 0;
        isTrading = true;
        
        // Close all open positions
        CloseAllPositions();
        
        // Update last reset time
        lastDailyResetTime = TimeCurrent();
        
        DebugLog("Daily Reset Complete. Trading Resumed.", true);
    }

    // Close all open positions
    void CloseAllPositions() {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == InpInputSymbol) {
                    trade.PositionClose(positionInfo.Ticket());
                }
            }
        }
    }

    // Validate Trade Conditions
    bool IsValidTradeCondition() {
        // Check if trading is allowed
        if (!isTrading) return false;

        // Check for existing position
        bool noActivePosition = !PositionSelect(InpInputSymbol);
        
        // Ensure minimum time between trades
        bool timeElapsed = (TimeCurrent() - lastTradeTime) > PeriodSeconds(InpChartTimeframe);
        
        return noActivePosition && timeElapsed;
    }

    // Calculate Trade Parameters
    void CalculateTradeLevels(bool isBuy, double& stopLoss, double& takeProfit) {
        double bid = SymbolInfoDouble(InpInputSymbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(InpInputSymbol, SYMBOL_ASK);
        double point = SymbolInfoDouble(InpInputSymbol, SYMBOL_POINT);

        if (isBuy) {
            stopLoss = bid - (InpStopLossPips * point * 10);
            takeProfit = bid + (InpTakeProfitPips * point * 10);
        } else {
            stopLoss = ask + (InpStopLossPips * point * 10);
            takeProfit = ask - (InpTakeProfitPips * point * 10);
        }
    }

    // Update Performance on Trade Result
    void UpdateTradeResult(bool isProfit) {
        if (!isProfit) {
            lossStreak++;
            
            // Multiply volume on losing streak
            currentVolume *= InpVolumeMultiplier;
            
            DebugLog("Stop Loss Hit. Loss Streak: " + IntegerToString(lossStreak) + 
                     ", New Volume: " + DoubleToString(currentVolume, 2), true);
            
            // Stop trading if max loss streak reached
            if (lossStreak >= InpMaxLossStreak) {
                isTrading = false;
                DebugLog("TRADING STOPPED: Maximum loss streak reached", true);
            }
        } else {
            // Reset loss streak on profitable trade
            lossStreak = 0;
        }
    }

public:
    // Constructor
    CRSILiveStrategy() {
        // Initialize variables
        currentVolume = InpInitialVolume;
        lossStreak = 0;
        isTrading = true;
        totalTrades = 0;
        profitableTrades = 0;
        unprofitableTrades = 0;
        totalProfit = 0;
        lastTradeTime = 0;
        lastDailyResetTime = 0;

        // Create RSI indicator handle
        rsiHandle = iRSI(InpInputSymbol, InpChartTimeframe, InpRsiPeriod, PRICE_CLOSE);
        
        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("Failed to create RSI indicator", true);
        }
    }

    // Destructor
    ~CRSILiveStrategy() {
        if (rsiHandle != INVALID_HANDLE) {
            IndicatorRelease(rsiHandle);
        }
    }

    // Execute Trade
    bool ExecuteTrade(bool isBuy) {
        // Check daily reset
        if (IsDailyResetTime()) {
            DailyReset();
        }

        // Validate trade conditions
        if (!IsValidTradeCondition()) {
            return false;
        }

        double stopLoss, takeProfit;
        CalculateTradeLevels(isBuy, stopLoss, takeProfit);

        // Adjust volume to prevent over-leveraging
        double maxVolume = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MAX);
        currentVolume = MathMin(currentVolume, maxVolume);

        // Execute trade
        bool tradeResult = isBuy ? 
            trade.Buy(currentVolume, InpInputSymbol, 0, stopLoss, takeProfit, InpStrategyName) :
            trade.Sell(currentVolume, InpInputSymbol, 0, stopLoss, takeProfit, InpStrategyName);

        if (tradeResult) {
            lastTradeTime = TimeCurrent();
            DebugLog(isBuy ? "BUY TRADE EXECUTED" : "SELL TRADE EXECUTED", true);
            return true;
        } else {
            DebugLog("TRADE EXECUTION FAILED: " + trade.ResultRetcodeDescription(), true);
            return false;
        }
    }

    // Check Trade Opportunity
    void CheckTradeOpportunity() {
        // Check daily reset
        if (IsDailyResetTime()) {
            DailyReset();
        }

        // Validate trading status
        if (!isTrading) return;

        // Validate RSI handle
        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("Invalid RSI handle", true);
            return;
        }

        // Copy RSI buffer
        double rsiBuffer[];
        ArraySetAsSeries(rsiBuffer, true);
        
        if (CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) <= 0) {
            DebugLog("Failed to copy RSI buffer", true);
            return;
        }

        // Get latest RSI value
        double rsi = rsiBuffer[0];
        DebugLog("Current RSI: " + DoubleToString(rsi, 2));

        // Execute trades based on RSI conditions
        if (IsValidTradeCondition()) {
            if (rsi <= InpRsiBuyThreshold) {
                ExecuteTrade(true);
            } else if (rsi >= InpRsiSellThreshold) {
                ExecuteTrade(false);
            }
        }
    }

    // Check and Update Trade Results
    void MonitorOpenTrades() {
        for (int i = PositionsTotal() - 1; i >= 0; i--) {
            if (positionInfo.SelectByIndex(i)) {
                if (positionInfo.Symbol() == InpInputSymbol) {
                    // Check for profit/loss
                    double profit = positionInfo.Profit();
                    UpdateTradeResult(profit > 0);
                }
            }
        }
    }
};

// Global strategy instance
CRSILiveStrategy *rsiStrategy = NULL;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Validate symbol
    if (Symbol() != InpInputSymbol) {
        DebugLog("ERROR: Strategy is designed for " + InpInputSymbol, true);
        return (INIT_FAILED);
    }

    // Create strategy instance
    rsiStrategy = new CRSILiveStrategy();
    
    return (rsiStrategy != NULL) ? INIT_SUCCEEDED : INIT_FAILED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (rsiStrategy != NULL) {
        delete rsiStrategy;
        rsiStrategy = NULL;
    }
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (rsiStrategy != NULL) {
        // Check for trade opportunities
        rsiStrategy.CheckTradeOpportunity();
        
        // Monitor and update existing trades
        rsiStrategy.MonitorOpenTrades();
    }
}
