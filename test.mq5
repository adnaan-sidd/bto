//+------------------------------------------------------------------+
//|                    EURUSD RSI Backtest Trading Strategy          |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window

#include <Trade\Trade.mqh>
#include <MovingAverages.mqh>

// Logging Function with Enhanced Debugging
void DebugLog(string message, bool isImportant = false) {
    string prefix = isImportant ? "CRITICAL: " : "";
    Print(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + prefix + message);
}

// Strategy Configuration
input string InpStrategyName = "EURUSD_RSI_Backtest_Strategy";
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

// Global Strategy Class
class CRSIBacktestStrategy {
private:
    CTrade trade;
    double currentVolume;
    int lossStreak;
    bool isTrading;
    int rsiHandle;
    datetime lastTradeTime;

    // Performance tracking
    int totalTrades;
    int profitableTrades;
    int unprofitableTrades;
    double totalProfit;

    // Validate Trade Conditions
    bool IsValidTradeCondition() {
        // Ensure no active position and enough time between trades
        bool noActivePosition = !PositionSelect(InpInputSymbol);
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

    // Update Performance Metrics
    void UpdatePerformanceMetrics(double profit) {
        totalTrades++;
        totalProfit += profit;
        
        if (profit > 0) {
            profitableTrades++;
        } else {
            unprofitableTrades++;
            lossStreak++;
            
            // Adjust volume on losing streak
            if (lossStreak > 1) {
                currentVolume *= InpVolumeMultiplier;
            }
        }

        // Stop trading if max loss streak reached
        if (lossStreak >= InpMaxLossStreak) {
            isTrading = false;
            DebugLog("TRADING STOPPED: Max loss streak reached", true);
        }
    }

public:
    // Constructor
    CRSIBacktestStrategy() {
        // Initialize variables
        currentVolume = InpInitialVolume;
        lossStreak = 0;
        isTrading = true;
        totalTrades = 0;
        profitableTrades = 0;
        unprofitableTrades = 0;
        totalProfit = 0;
        lastTradeTime = 0;

        // Create RSI indicator handle
        rsiHandle = iRSI(InpInputSymbol, InpChartTimeframe, InpRsiPeriod, PRICE_CLOSE);
        
        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("Failed to create RSI indicator", true);
        }
    }

    // Destructor to release resources
    ~CRSIBacktestStrategy() {
        if (rsiHandle != INVALID_HANDLE) {
            IndicatorRelease(rsiHandle);
        }
    }

    // Execute Trade
    bool ExecuteTrade(bool isBuy) {
        // Check if trading is allowed
        if (!isTrading || !IsValidTradeCondition()) {
            DebugLog("Trade conditions not met. Skipping trade.", true);
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

    // Check RSI Trade Opportunity
    void CheckTradeOpportunity() {
        if (!isTrading) return;

        // Ensure valid RSI handle
        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("Invalid RSI handle. Cannot check trade opportunity.", true);
            return;
        }

        // Copy RSI buffer
        double rsiBuffer[];
        ArraySetAsSeries(rsiBuffer, true);
        
        if (CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) <= 0) {
            DebugLog("Failed to copy RSI buffer", true);
            return;
        }

        // Use the latest RSI value
        double rsi = rsiBuffer[0];

        // Debug RSI value
        DebugLog("Current RSI: " + DoubleToString(rsi, 2));

        // Trade conditions
        if (IsValidTradeCondition()) {
            if (rsi <= InpRsiBuyThreshold) {
                ExecuteTrade(true); // Buy signal
            } else if (rsi >= InpRsiSellThreshold) {
                ExecuteTrade(false); // Sell signal
            }
        }
    }

    // Performance Report
    void PrintPerformanceReport() {
        DebugLog("==== Strategy Performance Report ====", true);
        DebugLog("Total Trades: " + IntegerToString(totalTrades), true);
        DebugLog("Profitable Trades: " + IntegerToString(profitableTrades), true);
        DebugLog("Unprofitable Trades: " + IntegerToString(unprofitableTrades), true);
        DebugLog("Total Profit: " + DoubleToString(totalProfit, 2), true);
    }
};

// Global strategy instance
CRSIBacktestStrategy *rsiStrategy = NULL;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    // Validate symbol
    if (Symbol() != InpInputSymbol) {
        DebugLog("ERROR: Strategy is designed for " + InpInputSymbol + ". Current symbol: " + Symbol(), true);
        return (INIT_FAILED);
    }

    // Check if running in tester
    if (!MQLInfoInteger(MQL_TESTER)) {
        DebugLog("Script intended for Strategy Tester mode", true);
        return (INIT_FAILED);
    }

    // Create strategy instance
    rsiStrategy = new CRSIBacktestStrategy();
    
    return (rsiStrategy != NULL) ? INIT_SUCCEEDED : INIT_FAILED;
}

//+------------------------------------------------------------------+
//| Expert Deinitialization Function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
    if (rsiStrategy != NULL) {
        rsiStrategy.PrintPerformanceReport();
        delete rsiStrategy;
        rsiStrategy = NULL;
    }
}

//+------------------------------------------------------------------+
//| Expert Tick Function                                             |
//+------------------------------------------------------------------+
void OnTick() {
    if (rsiStrategy != NULL) {
        rsiStrategy.CheckTradeOpportunity();
    }
}
