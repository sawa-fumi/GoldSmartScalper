# GoldSmartScalper

GOLD (XAUUSD) scalping signal indicator for MetaTrader 5.

## Target environment

- Platform: MT5
- Broker baseline: Vantage Standard
- Symbol baseline: XAUUSD / xauusd
- Intended chart timeframes: M1 to M5

## v1.2.0 — faster signal timing

`GoldSmartScalper_v1.2.0.mq5` focuses on reducing the delay seen in v1.1.0 while keeping signals on closed candles only.

### Early Signal modes

- `Early_Signal_Mode = 0` — v1.1-style confirmed close breakout. Slowest / strictest.
- `Early_Signal_Mode = 1` — Normal early mode. A wick break can qualify before a full close BOS. Default.
- `Early_Signal_Mode = 2` — Aggressive early mode. Can also qualify a strong momentum candle approaching the breakout level. Fastest, but more false signals are expected.

### New parameters

- `Min_Break_Pips = 3.0` — minimum wick breakout beyond the prior range.
- `Pullback_Max_Pips = 8.0` — maximum close-back distance allowed after a wick breakout.
- `Momentum_Acceleration_Use = true` — enables momentum acceleration for Aggressive mode.
- `ATR_Change_Ratio_Threshold = 0.15` — ATR acceleration threshold.
- `Aggressive_NearBreak_Pips = 4.0` — how close price can be to the prior swing level in Aggressive mode.

### Important design choice

v1.2.0 does **not** draw signals on the currently forming candle. This intentionally avoids the easiest source of repainting. The speed improvement comes from earlier breakout logic on the latest closed candle rather than waiting only for a close beyond the BOS level.

### Recommended first test

Start with:

- `Early_Signal_Mode = 1`
- `Use_HTF_Trend_Filter = false`
- `Trade_Only_Trend_Direction = false`
- `HTF_Mismatch_Mode = 0`
- `Signal_Strength_Threshold = 50`
- `Counter_Trend_Min_Score = 45`
- `UseSessionFilter = false`

If signals are still late, test `Early_Signal_Mode = 2`. If mode 2 produces too many false signals, return to mode 1 before changing other filters.

## v1.1.0

`GoldSmartScalper_v1.1.0.mq5` keeps the v1.0.0 base logic but makes H1/H4 filtering optional so M1-M5 scalping can take short-term counter-trend setups.

Main additions include optional HTF direction filtering, separate trend/counter-trend arrows, signal-score thresholds, and HTF mismatch handling.

## v1.0.0

`GoldSmartScalper_v1.0.0.mq5` is preserved as the first stable base version with EMA structure, H1/H4 filters, ATR, ADX, RSI, EMA slope, BOS, MA breakthrough block, optional sessions, and alerts.

## Install in MT5

1. Download the desired `.mq5` file.
2. MT5: `File > Open Data Folder`.
3. Open `MQL5 > Indicators`.
4. Copy the `.mq5` file there.
5. Open MetaEditor (F4).
6. Open the file and press F7 to compile.
7. Return to MT5 and refresh Navigator > Indicators.
8. Attach it to XAUUSD M1 first, then test M5.

## Push notification

Configure `Tools > Options > Notifications` in MT5 first. `EnablePushNotification` sends only after the terminal notification setup is complete.

## v1.2.0 test request

Please report the MetaEditor errors/warnings result, then compare v1.1.0 and v1.2.0 on the same XAUUSD M1 section. The most useful feedback is whether v1.2.0 enters 1–3 candles earlier, whether the first move is captured better, and whether false signals increase.

This is a signal indicator, not an automated trading system. Forward-test before using it for live-risk decisions.
