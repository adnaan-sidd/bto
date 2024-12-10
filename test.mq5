//+------------------------------------------------------------------+
//|                    EURUSD RSI Martingale Trading Strategy        |
//+------------------------------------------------------------------+
#property strict
#property indicator_chart_window
#property indicator_separate_window
#property indicator_minimum 0
#property indicator_maximum 100
#property indicator_level1 30
#property indicator_level2 70
#property indicator_levelcolor clrSilver

#include <Trade\Trade.mqh>

// Enhanced Logging Function
void DebugLog(string message, bool isImportant = false) {
    string prefix = isImportant ? "CRITICAL: " : "";
    Print(TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + " | " + prefix + message);
}

// Strategy Configuration
input string InpStrategyName = "EURUSD_RSI_Martingale_Strategy";
input string InpInputSymbol = "EURUSD";
input ENUM_TIMEFRAMES InpChartTimeframe = PERIOD_M1;
input ENUM_APPLIED_PRICE InpRsiAppliedPrice = PRICE_CLOSE;

// Trading Parameters
input double InpInitialVolume = 0.10;
input int InpTakeProfitPips = 30;
input int InpStopLossPips = 10;
input int InpRsiPeriod = 14;
input double InpRsiBuyThreshold = 35.0;
input double InpRsiSellThreshold = 75.0;
input int InpMaxLossStreak = 7;
input double InpVolumeMultiplier = 2.0;
input double InpMaxAllowedVolume = 10.0; // Maximum allowed trade volume

// Global Variables
class CRSIBacktestStrategy {
private:
    CTrade trade;
    double currentBuyVolume;
    double currentSellVolume;
    int buyLossStreak;
    int sellLossStreak;
    bool isTrading;
    int rsiHandle;
    double rsiBuffer[];
    bool rsiBuyMet;
    bool rsiSellMet;

    // Validate Trade Volume
    bool ValidateTradeVolume(double& volume) {
        double minVolume = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MIN);
        double maxVolume = MathMin(SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_MAX), InpMaxAllowedVolume);
        double volumeStep = SymbolInfoDouble(InpInputSymbol, SYMBOL_VOLUME_STEP);

        volume = MathMax(minVolume, volume);
        volume = MathMin(volume, maxVolume); // Ensure volume does not exceed max allowed volume
        volume = NormalizeDouble(MathRound(volume / volumeStep) * volumeStep, 2);

        if (volume < minVolume || volume > maxVolume) {
            DebugLog("CRITICAL: Volume validation failed. Volume: " + DoubleToString(volume, 4), true);
            return false;
        }

        return true;
    }

    // Calculate Trade Levels
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

    // Get Current RSI Value
    double GetCurrentRSI() {
        double rsi[];
        ArraySetAsSeries(rsi, true);
        int copied = CopyBuffer(rsiHandle, 0, 0, 1, rsi);
        return (copied > 0) ? rsi[0] : 0;
    }

    // Check Last Trade Result
    void CheckLastTradeResult(bool isBuy) {
        ulong ticket = trade.ResultOrder();
        if (ticket > 0) {
            double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double exitPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double stopLoss = PositionGetDouble(POSITION_SL);
            double takeProfit = PositionGetDouble(POSITION_TP);

            if ((isBuy && exitPrice >= takeProfit) || (!isBuy && exitPrice <= takeProfit)) {
                // Take Profit hit
                if (isBuy) {
                    buyLossStreak = 0;
                } else {
                    sellLossStreak = 0;
                }
            } else if ((isBuy && exitPrice <= stopLoss) || (!isBuy && exitPrice >= stopLoss)) {
                // Stop Loss hit
                if (isBuy) {
                    buyLossStreak++;
                } else {
                    sellLossStreak++;
                }
            }
        }
    }

public:
    CRSIBacktestStrategy() {
        currentBuyVolume = InpInitialVolume;
        currentSellVolume = InpInitialVolume;
        buyLossStreak = 0;
        sellLossStreak = 0;
        isTrading = true;
        rsiHandle = INVALID_HANDLE;
        rsiBuyMet = false;
        rsiSellMet = false;
    }

    // Initialize RSI Indicator
    bool Init() {
        rsiHandle = iRSI(InpInputSymbol, InpChartTimeframe, InpRsiPeriod, InpRsiAppliedPrice);
        if (rsiHandle == INVALID_HANDLE) {
            DebugLog("RSI Indicator Initialization Failed", true);
            return false;
        }
        ArraySetAsSeries(rsiBuffer, true);
        return true;
    }

    // Execute Trade with Advanced Checks
    bool ExecuteTrade(bool isBuy) {
        if (!isTrading) {
            DebugLog("Trading is stopped due to max loss streak.", true);
            return false;
        }

        double stopLoss, takeProfit;
        CalculateTradeLevels(isBuy, stopLoss, takeProfit);

        double tradeVolume = isBuy ? currentBuyVolume : currentSellVolume;
        if (!ValidateTradeVolume(tradeVolume)) {
            DebugLog("Invalid trade volume. Trade canceled.", true);
            return false;
        }

        bool tradeResult = isBuy ? 
            trade.Buy(tradeVolume, InpInputSymbol, 0, stopLoss, takeProfit, InpStrategyName) :
            trade.Sell(tradeVolume, InpInputSymbol, 0, stopLoss, takeProfit, InpStrategyName);

        if (tradeResult) {
            DebugLog(isBuy ? "BUY TRADE EXECUTED" : "SELL TRADE EXECUTED", true);
            DebugLog("Trade Details: Volume=" + DoubleToString(tradeVolume, 2) + 
                     ", SL=" + DoubleToString(stopLoss, _Digits) + 
                     ", TP=" + DoubleToString(takeProfit, _Digits), false);
            CheckLastTradeResult(isBuy);
            return true;
        } else {
            DebugLog("TRADE EXECUTION FAILED: " + trade.ResultRetcodeDescription(), true);
            return false;
        }
    }

    // Check and Update Trade Metrics
    void CheckTradeConditions() {
        if (PositionsTotal() > 0) return;

        double currentRSI = GetCurrentRSI();

        // Buy Condition
        if (currentRSI < InpRsiBuyThreshold || rsiBuyMet) {
            rsiBuyMet = true;
            if (buyLossStreak < InpMaxLossStreak) {
                if (ExecuteTrade(true)) {
                    currentBuyVolume *= InpVolumeMultiplier;
                }
            } else {
                isTrading = false;
                DebugLog("BUY TRADING STOPPED - Max Loss Streak Reached", true);
            }
        }

        // Sell Condition
        if (currentRSI > InpRsiSellThreshold || rsiSellMet) {
            rsiSellMet = true;
            if (sellLossStreak < InpMaxLossStreak) {
                if (ExecuteTrade(false)) {
                    currentSellVolume *= InpVolumeMultiplier;
                }
            } else {
                isTrading = false;
                DebugLog("SELL TRADING STOPPED - Max Loss Streak Reached", true);
            }
        }
    }

    // Cleanup Resources
    void CleanUp() {
        if (rsiHandle != INVALID_HANDLE) {
            IndicatorRelease(rsiHandle);
        }
    }
};

// Create Strategy Instance
CRSIBacktestStrategy strategy;

// Initialization Function
int OnInit() {
    if (!strategy.Init()) {
        return(INIT_FAILED);
    }
    DebugLog("Strategy Initialized: EURUSD RSI Martingale", true);
    return(INIT_SUCCEEDED);
}

// Tick Function
void OnTick() {
    strategy.CheckTradeConditions();
}

// Deinitialization
void OnDeinit(const int reason) {
    strategy.CleanUp();
}
