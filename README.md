# Swift Algo Bot - MT5 Expert Advisor

Automated multi-confluence trading bot for MetaTrader 5 with ATR-based risk management, trailing stops, and a real-time on-chart dashboard.

## Features

- **7-Point Confluence Engine** — Signals require agreement from multiple indicators before entering:
  1. EMA Crossover (Fast/Slow with trend filter)
  2. RSI (Overbought/Oversold bounce detection)
  3. MACD (Histogram crossover confirmation)
  4. Bollinger Bands (Band touch reversal)
  5. ADX (Trend strength filter)
  6. Stochastic (K/D crossover in extremes)
  7. Price Action (Engulfing candle patterns)

- **Smart Risk Management**
  - Percentage-based or fixed lot sizing
  - ATR-based dynamic Stop Loss / Take Profit
  - Trailing stop (ATR or fixed)
  - Auto break-even

- **Trade Filters**
  - Max spread filter
  - Trading hours restriction
  - Max simultaneous positions limit
  - Day-of-week filters (Sunday/Friday)

- **Live Dashboard**
  - Trend direction and signal status
  - All 7 sub-signal statuses
  - RSI, ATR, ADX values
  - Open positions, floating P/L, win rate, spread
  - Toggle with `D` key

- **Alerts**
  - Popup, sound, push notification, and email
  - Configurable cooldown to prevent spam

- **Emergency Controls**
  - Press `X` to close all positions instantly

## Installation

1. Copy files into your MT5 data folder:

```
MQL5/
├── Experts/
│   └── SwiftAlgoBot.mq5        ← Main EA file
└── Include/
    ├── SignalEngine.mqh         ← Signal confluence engine
    ├── TradeManager.mqh         ← Trade execution & risk
    ├── Dashboard.mqh            ← On-chart dashboard
    └── AlertSystem.mqh          ← Alert manager
```

2. **Find your MT5 data folder**: In MetaTrader 5, go to `File → Open Data Folder`

3. Copy the files:
   - `Experts/SwiftAlgoBot.mq5` → `MQL5/Experts/SwiftAlgoBot.mq5`
   - All files from `Include/` → `MQL5/Include/` (or a subfolder like `MQL5/Include/SwiftAlgo/`)

4. In MetaEditor, open `SwiftAlgoBot.mq5` and press **Compile** (F7)

5. In MT5, refresh the Navigator panel (`Ctrl+N`), find **SwiftAlgoBot** under Expert Advisors

6. Drag it onto a chart. Configure the input parameters and click OK.

7. Make sure **Algo Trading** is enabled (the button on the toolbar).

## Recommended Settings

| Parameter | Scalping (M5-M15) | Swing (H1-H4) | Position (D1) |
|---|---|---|---|
| EMA Fast | 5 | 9 | 9 |
| EMA Slow | 13 | 21 | 21 |
| EMA Trend | 34 | 50 | 100 |
| Min Confluence | 4 | 3 | 3 |
| SL Multiplier | 1.0 | 1.5 | 2.0 |
| TP Multiplier | 1.5 | 2.5 | 3.0 |
| Risk % | 0.5 | 1.0 | 1.5 |
| Max Spread | 15 | 30 | 50 |

## Backtesting

1. Open the Strategy Tester (`Ctrl+R`)
2. Select **SwiftAlgoBot**
3. Set your symbol, timeframe, and date range
4. Choose **Every tick based on real ticks** for best accuracy
5. Configure inputs in the Inputs tab
6. Click **Start**

## Important Notes

- Always test on a **demo account** first
- Start with **Min Confluence = 4** for more conservative entries
- The bot only trades when the confluence score meets or exceeds your threshold
- Higher confluence = fewer but higher-quality trades
- ATR-based stops automatically adapt to volatility
- The dashboard updates every second to minimize CPU usage

## Keyboard Shortcuts

| Key | Action |
|---|---|
| `D` | Toggle dashboard on/off |
| `X` | Emergency close all positions |

## License

For personal use. Trade at your own risk. No guarantees of profit.
