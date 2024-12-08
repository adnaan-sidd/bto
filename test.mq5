//+------------------------------------------------------------------+
//|                    EURUSD RSI Martingale Trading Strategy        |
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
input string InpStrategyName = "EURUSD_RSI_Martingale_Strategy";
input string InpInputSymbol = "EURUSD"; // Trading Symbol
input ENUM_TIMEFRAMES InpChartTimeframe = PERIOD_M15; // 15-Minute Timeframe

// Trading Parameters
input double InpInitialVolume = 0.01; // Initial Volume (equivalent to Lot Size)
input int InpTakeProfitPips = 30; // Take Profit in Pips
input int InpStopLossPips = 10; // Stop Loss in Pips
input int InpRsiPeriod = 14; // RSI Period
input double InpRsiBuyThreshold = 35.0; // Buy Threshold (below 35)
input double InpRsiSellThreshold = 75.0; // Sell Threshold (above 75)

// Risk Management Inputs
input int InpMaxLossStreak = 7; // Max Stop Loss Hit Streak
input double InpVolumeMultiplier = 2.0; // Volume Multiplier on Losing Streak

// Global Strategy Class
class CRSIBacktestStrategy {
private:
    CTrade trade;
    double currentVolume;
    int lossStreak;
    bool isTrading;
    datetime lastTradeTime;
    bool activeTradeExists;
    bool isActiveTradeBuy;

    // Flags to track first buy and sell trades
    bool firstBuyTradeExecuted;
    bool firstSellTradeExecuted;

    int rsiHandle;  // RSI indicator handle
    double rsiBuffer[];

    // Validate Trade Volume
    bool ValidateTradeVolume(double& volume) {
        double minVolume = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MIN);
        double maxVolume = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MAX);
        double volumeStep = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_STEP);

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
            if (profit > 0) {
                currentVolume = InpInitialVolume; // Reset volume after TP
                lossStreak = 0; // Reset loss streak
            } else {
                lossStreak++;
                currentVolume *= InpVolumeMultiplier; // Multiply volume on SL hit
            }

            if (lossStreak >= InpMaxLossStreak) {
                isTrading = false; // Stop trading after 7 consecutive losses
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
    }

    // Release resources
    void CleanUp() {
        if (rsiHandle != INVALID_HANDLE) {
            IndicatorRelease(rsiHandle);
        }
    }

    // Execute Trade
    bool ExecuteTrade(bool isBuy) {
        if (!isTrading) {
            DebugLog("Trading is stopped due to 7 consecutive SL hits.", true);
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
            profit *= currentVolume * SymbolInfoDouble(InpInputSymbol, SYMBOL_TRADE_CONTRACT_SIZE);
            UpdatePerformanceMetrics(profit, positionClosed);

            // Place a new trade in the same direction with updated volume
            ExecuteTrade(isActiveTradeBuy);
        }
    }

    // Check for Trade Opportunity based on RSI and conditions
    void CheckTradeOpportunity() {
        if (lossStreak >= InpMaxLossStreak) {
            isTrading = false;
            DebugLog("Trading stopped due to 7 consecutive SL hits.", true);
            return;
        }

        if (!activeTradeExists) {
            double rsiValue = 0.0;
            if (CopyBuffer(rsiHandle, 0, 0, 1, rsiBuffer) > 0) {
                rsiValue = rsiBuffer[0];
            }

            if (!firstBuyTradeExecuted && rsiValue < InpRsiBuyThreshold) {
                ExecuteTrade(true); // Buy Trade on RSI < 35
                firstBuyTradeExecuted = true;
            }

            if (!firstSellTradeExecuted && rsiValue > InpRsiSellThreshold) {
                ExecuteTrade(false); // Sell Trade on RSI > 75
                firstSellTradeExecuted = true;
            }
        }

        CheckPositionStatus();
    }

    // Initialization of RSI handle
    void Init() {
        rsiHandle = iRSI(InpInputSymbol, InpChartTimeframe, InpRsiPeriod, PRICE_CLOSE);
        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("Failed to initialize RSI indicator", true);
        } else {
            ArraySetAsSeries(rsiBuffer, true); // Ensure the buffer is aligned as a time series
        }
    }
};

// Create the Strategy Instance
CRSIBacktestStrategy strategy;

int OnInit() {
    strategy.Init(); // Initialize strategy
    DebugLog("Strategy Initialized: " + InpStrategyName, true);
    return(INIT_SUCCEEDED);
}

void OnTick() {
    strategy.CheckTradeOpportunity();
}

void OnDeinit(const int reason) {
    strategy.CleanUp(); // Clean up resources
}
