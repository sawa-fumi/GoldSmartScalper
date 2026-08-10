# GoldSmartScalper

GOLD (XAUUSD) scalping signal indicator for MetaTrader 5.

## Target environment

- Platform: MT5
- Broker baseline: Vantage
- Account baseline: Standard
- Symbol baseline: XAUUSD / xauusd
- Intended chart timeframes: M1 to M5
- Signal timing: closed candles only (no signal on candle 0)

## v1.1.0

`GoldSmartScalper_v1.1.0.mq5` keeps the v1.0.0 base logic but changes the higher-timeframe treatment so M1-M5 scalping can optionally ignore H1/H4 direction.

### Main changes

- Higher-timeframe filtering is optional.
- Default `Use_HTF_Trend_Filter = false` for scalping.
- `Trade_Only_Trend_Direction` can restrict signals to H1/H4 direction when desired.
- `HTF_Mismatch_Mode`
  - 0 = ignore mismatch
  - 1 = soft penalty
  - 2 = block mismatch
- Counter-trend signals relative to H1/H4 are drawn separately.
- BUY trend = blue arrow.
- SELL trend = red arrow.
- BUY counter-trend = aqua arrow.
- SELL counter-trend = magenta arrow.
- Signal strength scoring (0-100) is used as a threshold gate.
- `Signal_Strength_Threshold` controls normal signals.
- `Counter_Trend_Min_Score` controls counter-trend signals.
- MA breakthrough block remains optional.
- ATR low-volatility / spike block, ADX, RSI, EMA slope and BOS remain active.

### Recommended scalping start settings

- `Use_HTF_Trend_Filter = false`
- `Trade_Only_Trend_Direction = false`
- `HTF_Mismatch_Mode = 0`
- `Signal_Strength_Threshold = 50`
- `Counter_Trend_Min_Score = 45`
- `UseSessionFilter = false` initially

This setup allows M1-M5 conditions to generate a short signal even while H1/H4 are still bullish, which is the behavior requested after the first v1.0.0 chart test.

### Trend-following setup

If you prefer stronger higher-timeframe alignment:

- `Use_HTF_Trend_Filter = true`
- `Trade_Only_Trend_Direction = true`
- `HTF_Mismatch_Mode = 2`
- raise signal thresholds if you want fewer signals

## v1.0.0

`GoldSmartScalper_v1.0.0.mq5` is preserved as the first stable base version.

Its main filters are:

- EMA 20 / 50 / 100 / 200 structure
- EMA20 slope (angle proxy)
- price position
- H1/H4 filters
- ATR abnormal-volatility filter
- ADX minimum-strength filter
- RSI overheat filter
- BOS breakout confirmation
- large EMA20 body-cross breakthrough block
- optional London / New York session filter
- popup / push / sound alerts

## Install in MT5

1. Download the desired `.mq5` file.
2. In MT5 choose `File > Open Data Folder`.
3. Open `MQL5 > Indicators`.
4. Copy the `.mq5` file there.
5. Open MetaEditor (F4).
6. Open the file and press F7 to compile.
7. Return to MT5 and refresh Navigator > Indicators.
8. Attach it to XAUUSD M1 first, then test M5.

## Push notification

In MT5, configure `Tools > Options > Notifications` first. `EnablePushNotification` only sends through MT5 after the terminal itself is configured.

## Test request for v1.1.0

Please report:

- MetaEditor compile result: errors / warnings
- whether the previously missed short area now receives a magenta counter-trend SELL signal
- M1 signal frequency during London and New York
- whether arrows are too early / late / frequent / rare
- screenshots of good and bad signals

This is a signal indicator, not an automated trading system. Forward-test before using it for live-risk decisions.

## Planned next steps

- v1.1.x: tune thresholds and signal frequency from forward-test results
- v1.2.0: add FVG confirmation
- v1.3.0: add Order Block confirmation
- later: statistics / richer score display
