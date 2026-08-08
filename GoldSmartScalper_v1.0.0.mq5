#property copyright "GoldSmartScalper"
#property version   "1.00"
#property strict
#property indicator_chart_window
#property indicator_plots 2
#property indicator_buffers 2

#property indicator_label1  "BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2

input group "=== Core ==="
input int    MaxBarsToScan            = 500;
input int    BOSLookback              = 8;
input bool   UseH1Filter              = true;
input bool   UseH4Filter              = true;

input group "=== EMA Structure ==="
input int    EMAFastPeriod            = 20;
input int    EMAMidPeriod             = 50;
input int    EMASlowPeriod            = 100;
input int    EMATrendPeriod           = 200;
input int    AngleLookbackBars        = 8;
input double MinFastMASlopePips       = 6.0;

input group "=== ATR Volatility Filter ==="
input int    ATRPeriod                = 14;
input int    ATRAverageBars           = 30;
input double ATRLowRatio              = 0.70;
input double ATRSpikeRatio            = 2.20;

input group "=== ADX / RSI ==="
input int    ADXPeriod                = 14;
input double ADXMin                   = 22.0;
input int    RSIPeriod                = 14;
input double RSIBuyMax                = 75.0;
input double RSISellMin               = 25.0;

input group "=== MA Breakthrough Block ==="
input bool   UseBreakthroughBlock     = true;
input double MaxBodyThroughEMA_ATR    = 0.55;

input group "=== Session Filter (SERVER TIME) ==="
input bool   UseSessionFilter         = false;
input int    LondonStartHour          = 8;
input int    LondonEndHour            = 17;
input int    NewYorkStartHour         = 13;
input int    NewYorkEndHour           = 22;

input group "=== Signal / Alert ==="
input double ArrowOffsetATR           = 0.30;
input bool   EnablePopupAlert         = true;
input bool   EnablePushNotification   = true;
input bool   EnableSound              = false;
input string AlertSoundFile           = "alert.wav";

//--- indicator buffers
double BuyBuffer[];
double SellBuffer[];

//--- indicator handles (current timeframe)
int hEMA20 = INVALID_HANDLE;
int hEMA50 = INVALID_HANDLE;
int hEMA100 = INVALID_HANDLE;
int hEMA200 = INVALID_HANDLE;
int hATR = INVALID_HANDLE;
int hADX = INVALID_HANDLE;
int hRSI = INVALID_HANDLE;

//--- higher timeframe handles
int hH1EMA50 = INVALID_HANDLE;
int hH1EMA200 = INVALID_HANDLE;
int hH4EMA50 = INVALID_HANDLE;
int hH4EMA200 = INVALID_HANDLE;

//--- state
datetime g_lastAlertBar = 0;

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
double PipSize()
{
   // GOLD brokers vary in digits. This keeps "pip" practical for XAUUSD.
   // 2/3 digits -> 0.10, 1 digit -> 0.10, otherwise 10 points.
   if(_Digits <= 3)
      return 0.10;
   return _Point * 10.0;
}

bool CopyOne(const int handle,const int buffer_num,const int shift,double &value)
{
   double tmp[1];
   if(handle == INVALID_HANDLE)
      return false;
   if(CopyBuffer(handle,buffer_num,shift,1,tmp) != 1)
      return false;
   value = tmp[0];
   return MathIsValidNumber(value);
}

bool SessionAllowed(const datetime t)
{
   if(!UseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(t,dt);
   int h = dt.hour;

   bool london = (LondonStartHour <= LondonEndHour)
                  ? (h >= LondonStartHour && h < LondonEndHour)
                  : (h >= LondonStartHour || h < LondonEndHour);

   bool ny = (NewYorkStartHour <= NewYorkEndHour)
             ? (h >= NewYorkStartHour && h < NewYorkEndHour)
             : (h >= NewYorkStartHour || h < NewYorkEndHour);

   return (london || ny);
}

bool HigherTFTrend(const datetime t,const ENUM_TIMEFRAMES tf,
                   const int handleFast,const int handleSlow,
                   const bool wantLong)
{
   int shift = iBarShift(_Symbol,tf,t,false);
   if(shift < 0)
      return false;

   double fast,slow;
   if(!CopyOne(handleFast,0,shift,fast) || !CopyOne(handleSlow,0,shift,slow))
      return false;

   double c = iClose(_Symbol,tf,shift);
   if(c <= 0.0)
      return false;

   if(wantLong)
      return (fast > slow && c > fast);
   return (fast < slow && c < fast);
}

bool ATRNormal(const int shift,double &atrNow)
{
   if(!CopyOne(hATR,0,shift,atrNow) || atrNow <= 0.0)
      return false;

   double sum = 0.0;
   int count = 0;
   for(int k=shift+1; k<=shift+ATRAverageBars; k++)
   {
      double a;
      if(CopyOne(hATR,0,k,a) && a > 0.0)
      {
         sum += a;
         count++;
      }
   }

   if(count < MathMax(5,ATRAverageBars/2))
      return false;

   double avg = sum / count;
   if(avg <= 0.0)
      return false;

   double ratio = atrNow / avg;
   return (ratio >= ATRLowRatio && ratio <= ATRSpikeRatio);
}

bool BOSLong(const int shift,const double &high[],const double &close[],const int rates_total)
{
   if(shift + BOSLookback + 1 >= rates_total)
      return false;

   double priorHigh = -DBL_MAX;
   for(int k=shift+1; k<=shift+BOSLookback; k++)
      priorHigh = MathMax(priorHigh,high[k]);

   return close[shift] > priorHigh;
}

bool BOSShort(const int shift,const double &low[],const double &close[],const int rates_total)
{
   if(shift + BOSLookback + 1 >= rates_total)
      return false;

   double priorLow = DBL_MAX;
   for(int k=shift+1; k<=shift+BOSLookback; k++)
      priorLow = MathMin(priorLow,low[k]);

   return close[shift] < priorLow;
}

bool BreakthroughBlocked(const int shift,const double openPrice,const double closePrice,
                         const double ema20,const double atr)
{
   if(!UseBreakthroughBlock || atr <= 0.0)
      return false;

   double body = MathAbs(closePrice-openPrice);
   if(body < atr*MaxBodyThroughEMA_ATR)
      return false;

   bool crossed = ((openPrice > ema20 && closePrice < ema20) ||
                   (openPrice < ema20 && closePrice > ema20));
   return crossed;
}

void FireAlert(const bool isBuy,const datetime barTime,const double price)
{
   if(barTime == g_lastAlertBar)
      return;

   string side = isBuy ? "BUY" : "SELL";
   string tf = EnumToString((ENUM_TIMEFRAMES)_Period);
   string msg = StringFormat("GoldSmartScalper v1.0.0 %s %s %s @ %.*f",
                             _Symbol,tf,side,_Digits,price);

   if(EnablePopupAlert)
      Alert(msg);
   if(EnablePushNotification)
      SendNotification(msg);
   if(EnableSound)
      PlaySound(AlertSoundFile);

   g_lastAlertBar = barTime;
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,BuyBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellBuffer,INDICATOR_DATA);
   ArraySetAsSeries(BuyBuffer,true);
   ArraySetAsSeries(SellBuffer,true);

   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,"GoldSmartScalper v1.0.0");

   hEMA20  = iMA(_Symbol,_Period,EMAFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA50  = iMA(_Symbol,_Period,EMAMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA100 = iMA(_Symbol,_Period,EMASlowPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA200 = iMA(_Symbol,_Period,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   hATR    = iATR(_Symbol,_Period,ATRPeriod);
   hADX    = iADX(_Symbol,_Period,ADXPeriod);
   hRSI    = iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);

   hH1EMA50  = iMA(_Symbol,PERIOD_H1,EMAMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH1EMA200 = iMA(_Symbol,PERIOD_H1,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH4EMA50  = iMA(_Symbol,PERIOD_H4,EMAMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH4EMA200 = iMA(_Symbol,PERIOD_H4,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);

   if(hEMA20==INVALID_HANDLE || hEMA50==INVALID_HANDLE ||
      hEMA100==INVALID_HANDLE || hEMA200==INVALID_HANDLE ||
      hATR==INVALID_HANDLE || hADX==INVALID_HANDLE || hRSI==INVALID_HANDLE ||
      hH1EMA50==INVALID_HANDLE || hH1EMA200==INVALID_HANDLE ||
      hH4EMA50==INVALID_HANDLE || hH4EMA200==INVALID_HANDLE)
   {
      Print("GoldSmartScalper: failed to create indicator handles. Error=",GetLastError());
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hEMA20!=INVALID_HANDLE) IndicatorRelease(hEMA20);
   if(hEMA50!=INVALID_HANDLE) IndicatorRelease(hEMA50);
   if(hEMA100!=INVALID_HANDLE) IndicatorRelease(hEMA100);
   if(hEMA200!=INVALID_HANDLE) IndicatorRelease(hEMA200);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hH1EMA50!=INVALID_HANDLE) IndicatorRelease(hH1EMA50);
   if(hH1EMA200!=INVALID_HANDLE) IndicatorRelease(hH1EMA200);
   if(hH4EMA50!=INVALID_HANDLE) IndicatorRelease(hH4EMA50);
   if(hH4EMA200!=INVALID_HANDLE) IndicatorRelease(hH4EMA200);
}

//+------------------------------------------------------------------+
//| Main                                                             |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   int need = EMATrendPeriod + MathMax(BOSLookback,ATRAverageBars) + AngleLookbackBars + 20;
   if(rates_total < need)
      return 0;

   int maxShift = MathMin(MaxBarsToScan,rates_total-need);
   if(maxShift < 1)
      return rates_total;

   // Rebuild a limited historical window on every call. Simple and robust for v1.0.0.
   for(int i=maxShift; i>=1; i--)
   {
      BuyBuffer[i] = EMPTY_VALUE;
      SellBuffer[i] = EMPTY_VALUE;

      if(!SessionAllowed(time[i]))
         continue;

      double ema20,ema50,ema100,ema200,ema20Past;
      double adx,rsi,atr;

      if(!CopyOne(hEMA20,0,i,ema20) ||
         !CopyOne(hEMA50,0,i,ema50) ||
         !CopyOne(hEMA100,0,i,ema100) ||
         !CopyOne(hEMA200,0,i,ema200) ||
         !CopyOne(hEMA20,0,i+AngleLookbackBars,ema20Past) ||
         !CopyOne(hADX,0,i,adx) ||
         !CopyOne(hRSI,0,i,rsi))
         continue;

      if(!ATRNormal(i,atr))
         continue;

      if(adx < ADXMin)
         continue;

      bool structureLong  = (ema20 > ema50 && ema50 > ema100 && ema100 > ema200);
      bool structureShort = (ema20 < ema50 && ema50 < ema100 && ema100 < ema200);

      double slopePips = (ema20-ema20Past)/PipSize();
      bool angleLong  = (slopePips >= MinFastMASlopePips);
      bool angleShort = (slopePips <= -MinFastMASlopePips);

      bool priceLong  = (close[i] > ema20 && close[i] > ema50);
      bool priceShort = (close[i] < ema20 && close[i] < ema50);

      bool longOK = structureLong && angleLong && priceLong &&
                    (rsi < RSIBuyMax) && BOSLong(i,high,close,rates_total);

      bool shortOK = structureShort && angleShort && priceShort &&
                     (rsi > RSISellMin) && BOSShort(i,low,close,rates_total);

      if(BreakthroughBlocked(i,open[i],close[i],ema20,atr))
      {
         longOK = false;
         shortOK = false;
      }

      if(longOK && UseH1Filter)
         longOK = HigherTFTrend(time[i],PERIOD_H1,hH1EMA50,hH1EMA200,true);
      if(shortOK && UseH1Filter)
         shortOK = HigherTFTrend(time[i],PERIOD_H1,hH1EMA50,hH1EMA200,false);

      if(longOK && UseH4Filter)
         longOK = HigherTFTrend(time[i],PERIOD_H4,hH4EMA50,hH4EMA200,true);
      if(shortOK && UseH4Filter)
         shortOK = HigherTFTrend(time[i],PERIOD_H4,hH4EMA50,hH4EMA200,false);

      if(longOK)
         BuyBuffer[i] = low[i] - atr*ArrowOffsetATR;
      else if(shortOK)
         SellBuffer[i] = high[i] + atr*ArrowOffsetATR;
   }

   // Never signal on the forming candle.
   BuyBuffer[0] = EMPTY_VALUE;
   SellBuffer[0] = EMPTY_VALUE;

   // Alert only when the latest CLOSED candle has a signal.
   if(BuyBuffer[1] != EMPTY_VALUE)
      FireAlert(true,time[1],close[1]);
   else if(SellBuffer[1] != EMPTY_VALUE)
      FireAlert(false,time[1],close[1]);

   return rates_total;
}
