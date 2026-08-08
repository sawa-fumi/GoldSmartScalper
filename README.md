# GoldSmartScalper

GOLD (XAUUSD) scalping signal indicator for MetaTrader 5.

## v1.0.0 target environment

- Platform: MT5
- Broker baseline: Vantage
- Account baseline: Standard
- Symbol baseline: XAUUSD / xauusd
- Intended chart timeframes: M1 to M5
- Signal timing: closed candles only (no signal on candle 0)

## v1.0.0 logic

A BUY/SELL arrow is allowed only after the enabled filters agree:

- EMA 20 / 50 / 100 / 200 structure
- EMA20 slope (angle proxy)
- Price position relative to EMA20/EMA50
- H1 trend filter (EMA50 vs EMA200 + price position)
- H4 trend filter (EMA50 vs EMA200 + price position)
- ATR abnormal-volatility filter
  - blocks unusually low volatility
  - blocks ATR spikes
- ADX minimum-strength filter
- RSI overheat filter
- BOS breakout confirmation
- Large EMA20 body-cross breakthrough block
- Optional London / New York session filter
- Popup / Push / Sound alerts

## Important v1.0.0 defaults

The session filter is **OFF by default** because MT5 broker server time can vary and daylight-saving time changes London/New York alignment. First verify signals with it OFF. We can calibrate Vantage server time after observing the platform clock.

The indicator uses the current chart symbol, so attach it to the Vantage XAUUSD chart. Symbol capitalization is not hard-coded.

## Install in MT5

1. Download `GoldSmartScalper_v1.0.0.mq5`.
2. In MT5 choose `File > Open Data Folder`.
3. Open `MQL5 > Indicators`.
4. Copy the `.mq5` file there.
5. Open MetaEditor (F4).
6. Open the file and press F7 to compile.
7. Return to MT5 and refresh Navigator > Indicators.
8. Attach it to XAUUSD M1 first, then test M5.

## Push notification

In MT5, configure `Tools > Options > Notifications` first. The input `EnablePushNotification` only sends through MT5 after the terminal itself is configured.

## First test requested

Please report:

- MetaEditor compile result: errors / warnings
- M1: approximate number of arrows in one London + New York session
- M5: approximate number of arrows
- whether arrows appear too late / too often / too rarely
- screenshot of 2-3 good signals and 2-3 bad signals

Do not use v1.0.0 as an automated trading system. It is a signal indicator and needs forward testing before live-risk decisions.

## Planned next steps

- v1.0.1: fix compile/runtime issues and tune signal frequency
- v1.1.0: FVG confirmation
- v1.2.0: Order Block confirmation
- later: signal scoring / statistics
