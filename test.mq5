//+------------------------------------------------------------------+
//|                    EURUSD RSI Backtest Trading Strategy          |
//+------------------------------------------------------------------+
#property strict
#property indicator_separate_window

#include <Trade\Trade.mqh>
#include <MovingAverages.mqh>

// Enhanced Logging Function
void DebugLog(string message, bool isImportant = false) {
    string prefix = isImportant ? "CRITICAL: " : "";
    Print(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + prefix + message);
}

// Strategy Configuration
input string InpStrategyName = "EURUSD_RSI_Backtest_Strategy";
input string InpInputSymbol = "EURUSD"; // Trading Symbol
input ENUM_TIMEFRAMES InpChartTimeframe = PERIOD_M15; // 15-Minute Timeframe

// Trading Parameters
input double InpInitialVolume = 0.01; // Initial Volume (equivalent to Lot Size)
input int InpTakeProfitPips = 30; // Take Profit in Pips
input int InpStopLossPips = 10; // Stop Loss in Pips
input int InpRsiPeriod = 14; // RSI Period
input double InpRsiBuyThreshold = 30.0; // Buy Threshold
input double InpRsiSellThreshold = 70.0; // Sell Threshold

// Risk Management Inputs
input int InpMaxLossStreak = 7; // Max Stop Loss Hit Streak
input double InpVolumeMultiplier = 1.5; // Volume Multiplier on Losing Streak

// Global Strategy Class
class CRSIBacktestStrategy {
private:
    CTrade trade;
    double currentVolume;
    int lossStreak;
    bool isTrading;
    int rsiHandle;
    datetime lastTradeTime;
    bool activeTradeExists;
    bool isActiveTradeBuy;

    // Flags to track first buy and sell trades
    bool firstBuyTradeExecuted;
    bool firstSellTradeExecuted;

    // Performance tracking
    int totalTrades;
    int profitableTrades;
    int unprofitableTrades;
    double totalProfit;

    // Validate Trade Volume
    bool ValidateTradeVolume(double& volume) {
        double minVolume = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MIN);
        double maxVolume = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MAX);
        double volumeStep = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_STEP);

        // Log initial volume details for debugging
        DebugLog("Volume Parameters - Min: " + DoubleToString(minVolume, 4) + 
                 ", Max: " + DoubleToString(maxVolume, 4) + 
                 ", Step: " + DoubleToString(volumeStep, 4), false);

        volume = MathMax(minVolume, volume);
        volume = NormalizeDouble(MathRound(volume / volumeStep) * volumeStep, 2);

        if (volume < minVolume) {
            volume = minVolume;
            DebugLog("Adjusted volume to minimum: " + DoubleToString(volume, 4), true);
        }
        
        if (volume > maxVolume) {
            volume = maxVolume;
            DebugLog("Adjusted volume to maximum: " + DoubleToString(volume, 4), true);
        }

        if (volume < minVolume || volume > maxVolume) {
            DebugLog("CRITICAL: Volume validation failed. Volume: " + DoubleToString(volume, 4), true);
            return false;
        }

        return true;
    }

    // Validate Trade Conditions
    bool IsValidTradeCondition() {
        bool noActivePosition = !activeTradeExists;
        bool timeElapsed = (TimeCurrent() - lastTradeTime) > PeriodSeconds(InpChartTimeframe);
        return noActivePosition && timeElapsed;
    }

    // Calculate Trade Parameters
    void CalculateTradeLevels(bool isBuy, double& stopLoss, double& takeProfit) {
        double bid = SymbolInfoDouble(InpInputSymbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(InpInputSymbol, SYMBOL_ASK);
        double point = SymbolInfoDouble(InpInputSymbol, SYMBOL_POINT);

        if (isBuy) {
            stopLoss = NormalizeDouble(bid - (InpStopLossPips * point * 10), _Digits);
            takeProfit = NormalizeDouble(bid + (InpTakeProfitPips * point * 10), _Digits);
        } else {
            stopLoss = NormalizeDouble(ask + (InpStopLossPips * point * 10), _Digits);
            takeProfit = NormalizeDouble(ask - (InpTakeProfitPips * point * 10), _Digits);
        }
    }

    // Update Performance Metrics
    void UpdatePerformanceMetrics(double profit, bool isTradeClosed) {
        if (isTradeClosed) {
            totalTrades++;
            totalProfit += profit;
            
            if (profit > 0) {
                profitableTrades++;
                currentVolume = InpInitialVolume; // Reset volume after TP
                lossStreak = 0;
                firstBuyTradeExecuted = firstSellTradeExecuted = false; // Reset flags after profitable trade
            } else {
                unprofitableTrades++;
                lossStreak++;
                currentVolume *= InpVolumeMultiplier;
            }

            if (lossStreak >= InpMaxLossStreak) {
                isTrading = false;
                DebugLog("TRADING STOPPED: Max loss streak reached", true);
            }

            activeTradeExists = false;
        }
    }

public:
    // Constructor
    CRSIBacktestStrategy() {
        currentVolume = InpInitialVolume;
        lossStreak = 0;
        isTrading = true;
        activeTradeExists = false;
        firstBuyTradeExecuted = false;
        firstSellTradeExecuted = false;
        totalTrades = 0;
        profitableTrades = 0;
        unprofitableTrades = 0;
        totalProfit = 0;
        lastTradeTime = 0;

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

    // Execute Trade with Enhanced Volume Validation
    bool ExecuteTrade(bool isBuy) {
        if (!isTrading || !IsValidTradeCondition()) {
            DebugLog("Trade conditions not met. Skipping trade.", true);
            return false;
        }

        double stopLoss, takeProfit;
        CalculateTradeLevels(isBuy, stopLoss, takeProfit);

        double tradeVolume = currentVolume;
        if (!ValidateTradeVolume(tradeVolume)) {
            DebugLog("Invalid trade volume. Trade canceled.", true);
            return false;
        }

        bool tradeResult = isBuy ? 
            trade.Buy(tradeVolume, InpInputSymbol, 0, stopLoss, takeProfit, InpStrategyName) :
            trade.Sell(tradeVolume, InpInputSymbol, 0, stopLoss, takeProfit, InpStrategyName);

        if (tradeResult) {
            lastTradeTime = TimeCurrent();
            activeTradeExists = true;
            isActiveTradeBuy = isBuy;
            DebugLog(isBuy ? "BUY TRADE EXECUTED" : "SELL TRADE EXECUTED", true);
            DebugLog("Trade Details: Volume=" + DoubleToString(tradeVolume, 2) + 
                     ", SL=" + DoubleToString(stopLoss, _Digits) + 
                     ", TP=" + DoubleToString(takeProfit, _Digits), false);
            return true;
        } else {
            DebugLog("TRADE EXECUTION FAILED: " + trade.ResultRetcodeDescription(), true);
            return false;
        }
    }

    // Check Position Status and Update Metrics
    void CheckPositionStatus() {
        if (!activeTradeExists) return;

        bool positionClosed = false;
        double profit = 0;

        if (!PositionSelect(InpInputSymbol)) {
            positionClosed = true;
            profit = (isActiveTradeBuy) ? 
                (SymbolInfoDouble(InpInputSymbol, SYMBOL_BID) - PositionGetDouble(POSITION_PRICE_OPEN)) :
                (PositionGetDouble(POSITION_PRICE_OPEN) - SymbolInfoDouble(InpInputSymbol, SYMBOL_ASK));
        }

        if (positionClosed) {
            UpdatePerformanceMetrics(profit, true);
        }
    }

    // Check RSI Trade Opportunity
    void CheckTradeOpportunity() {
        if (!isTrading) return;

        if (activeTradeExists) {
            CheckPositionStatus();
            return;
        }

        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("Invalid RSI handle. Cannot check trade opportunity.", true);
            return;
        }

        double rsiBuffer[];
        ArraySetAsSeries(rsiBuffer, true);
        
        if (CopyBuffer(rsiHandle, 0, 0, 3, rsiBuffer) <= 0) {
            DebugLog("Failed to copy RSI buffer", true);
            return;
        }

        double rsi = rsiBuffer[0];
        DebugLog("Current RSI: " + DoubleToString(rsi, 2));

        if (IsValidTradeCondition()) {
            if (!firstBuyTradeExecuted && rsi <= InpRsiBuyThreshold) {
                ExecuteTrade(true);
                firstBuyTradeExecuted = true;
            } else if (!firstSellTradeExecuted && rsi >= InpRsiSellThreshold) {
                ExecuteTrade(false);
                firstSellTradeExecuted = true;
            } else if (firstBuyTradeExecuted || firstSellTradeExecuted) {
                ExecuteTrade(rsi <= InpRsiBuyThreshold);
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
        DebugLog("Current Loss Streak: " + IntegerToString(lossStreak), true);
    }
};

// Global strategy instance
CRSIBacktestStrategy *rsiStrategy = NULL;

//+------------------------------------------------------------------+
//| Expert Initialization Function                                   |
//+------------------------------------------------------------------+
int OnInit() {
    if (Symbol() != InpInputSymbol) {
        DebugLog("ERROR: Strategy is designed for " + InpInputSymbol + ". Current symbol: " + Symbol(), true);
        return (INIT_FAILED);
    }

    if (!MQLInfoInteger(MQL_TESTER)) {
        DebugLog("Script intended for Strategy Tester mode", true);
        return (INIT_FAILED);
    }

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
