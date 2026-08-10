#property copyright "GoldSmartScalper"
#property version   "1.10"
#property strict
#property indicator_chart_window
#property indicator_plots 4
#property indicator_buffers 4

#property indicator_label1  "BUY Trend"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "SELL Trend"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrTomato
#property indicator_width2  2

#property indicator_label3  "BUY Counter"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrAqua
#property indicator_width3  2

#property indicator_label4  "SELL Counter"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrMagenta
#property indicator_width4  2

input group "=== Core ==="
input int    MaxBarsToScan               = 500;
input int    BOSLookback                 = 8;
input double Signal_Strength_Threshold   = 50.0;
input double Counter_Trend_Min_Score     = 45.0;

input group "=== Higher Timeframe Filter ==="
input bool   Use_HTF_Trend_Filter        = false;
input bool   Trade_Only_Trend_Direction  = false;
input int    HTF_Mismatch_Mode           = 0;   // 0=ignore, 1=soft, 2=block
input bool   UseH1Filter                 = true;
input bool   UseH4Filter                 = true;

input group "=== EMA Structure ==="
input int    EMAFastPeriod               = 20;
input int    EMAMidPeriod                = 50;
input int    EMASlowPeriod               = 100;
input int    EMATrendPeriod              = 200;
input int    AngleLookbackBars           = 8;
input double MinFastMASlopePips          = 4.0;

input group "=== ATR Volatility Filter ==="
input int    ATRPeriod                   = 14;
input int    ATRAverageBars              = 30;
input double ATRLowRatio                 = 0.70;
input double ATRSpikeRatio               = 2.20;

input group "=== ADX / RSI ==="
input int    ADXPeriod                   = 14;
input double ADXMin                      = 20.0;
input int    RSIPeriod                   = 14;
input double RSIBuyMax                   = 75.0;
input double RSISellMin                  = 25.0;

input group "=== MA Breakthrough Block ==="
input bool   Use_MA_Break_Block          = true;
input double MaxBodyThroughEMA_ATR       = 0.70;

input group "=== Session Filter (SERVER TIME) ==="
input bool   UseSessionFilter            = false;
input int    LondonStartHour             = 8;
input int    LondonEndHour               = 17;
input int    NewYorkStartHour            = 13;
input int    NewYorkEndHour              = 22;

input group "=== Signal / Alert ==="
input double ArrowOffsetATR              = 0.30;
input bool   EnablePopupAlert            = true;
input bool   EnablePushNotification      = true;
input bool   EnableSound                 = false;
input string AlertSoundFile              = "alert.wav";

//--- buffers
double BuyTrendBuffer[];
double SellTrendBuffer[];
double BuyCounterBuffer[];
double SellCounterBuffer[];

//--- handles
int hEMA20=INVALID_HANDLE;
int hEMA50=INVALID_HANDLE;
int hEMA100=INVALID_HANDLE;
int hEMA200=INVALID_HANDLE;
int hATR=INVALID_HANDLE;
int hADX=INVALID_HANDLE;
int hRSI=INVALID_HANDLE;

int hH1EMA20=INVALID_HANDLE;
int hH1EMA50=INVALID_HANDLE;
int hH1EMA200=INVALID_HANDLE;
int hH4EMA20=INVALID_HANDLE;
int hH4EMA50=INVALID_HANDLE;
int hH4EMA200=INVALID_HANDLE;

datetime g_lastAlertBar=0;

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
double PipSize()
{
   if(_Digits<=3)
      return 0.10;
   return _Point*10.0;
}

bool CopyOne(const int handle,const int buffer_num,const int shift,double &value)
{
   double tmp[1];
   if(handle==INVALID_HANDLE)
      return false;
   if(CopyBuffer(handle,buffer_num,shift,1,tmp)!=1)
      return false;
   value=tmp[0];
   return MathIsValidNumber(value);
}

bool SessionAllowed(const datetime t)
{
   if(!UseSessionFilter)
      return true;

   MqlDateTime dt;
   TimeToStruct(t,dt);
   int h=dt.hour;

   bool london=(LondonStartHour<=LondonEndHour)
                ? (h>=LondonStartHour && h<LondonEndHour)
                : (h>=LondonStartHour || h<LondonEndHour);
   bool ny=(NewYorkStartHour<=NewYorkEndHour)
            ? (h>=NewYorkStartHour && h<NewYorkEndHour)
            : (h>=NewYorkStartHour || h<NewYorkEndHour);
   return (london || ny);
}

int TFDirection(const datetime t,const ENUM_TIMEFRAMES tf,
                const int hFast,const int hMid,const int hSlow)
{
   int shift=iBarShift(_Symbol,tf,t,false);
   if(shift<0)
      return 0;

   double fast,mid,slow;
   if(!CopyOne(hFast,0,shift,fast) || !CopyOne(hMid,0,shift,mid) || !CopyOne(hSlow,0,shift,slow))
      return 0;

   double c=iClose(_Symbol,tf,shift);
   if(c<=0.0)
      return 0;

   if(fast>mid && mid>slow && c>fast)
      return 1;
   if(fast<mid && mid<slow && c<fast)
      return -1;
   return 0;
}

int CombinedHTFDirection(const datetime t)
{
   int h1=0,h4=0;
   if(UseH1Filter)
      h1=TFDirection(t,PERIOD_H1,hH1EMA20,hH1EMA50,hH1EMA200);
   if(UseH4Filter)
      h4=TFDirection(t,PERIOD_H4,hH4EMA20,hH4EMA50,hH4EMA200);

   if(UseH1Filter && UseH4Filter)
   {
      if(h1==1 && h4==1) return 1;
      if(h1==-1 && h4==-1) return -1;
      return 0;
   }
   if(UseH1Filter) return h1;
   if(UseH4Filter) return h4;
   return 0;
}

bool ATRNormal(const int shift,double &atrNow)
{
   if(!CopyOne(hATR,0,shift,atrNow) || atrNow<=0.0)
      return false;

   double sum=0.0;
   int count=0;
   for(int k=shift+1;k<=shift+ATRAverageBars;k++)
   {
      double a;
      if(CopyOne(hATR,0,k,a) && a>0.0)
      {
         sum+=a;
         count++;
      }
   }
   if(count<MathMax(5,ATRAverageBars/2))
      return false;

   double avg=sum/count;
   if(avg<=0.0)
      return false;

   double ratio=atrNow/avg;
   return (ratio>=ATRLowRatio && ratio<=ATRSpikeRatio);
}

bool BOSLong(const int shift,const double &high[],const double &close[],const int rates_total)
{
   if(shift+BOSLookback+1>=rates_total)
      return false;
   double priorHigh=-DBL_MAX;
   for(int k=shift+1;k<=shift+BOSLookback;k++)
      priorHigh=MathMax(priorHigh,high[k]);
   return close[shift]>priorHigh;
}

bool BOSShort(const int shift,const double &low[],const double &close[],const int rates_total)
{
   if(shift+BOSLookback+1>=rates_total)
      return false;
   double priorLow=DBL_MAX;
   for(int k=shift+1;k<=shift+BOSLookback;k++)
      priorLow=MathMin(priorLow,low[k]);
   return close[shift]<priorLow;
}

bool BreakthroughBlocked(const double openPrice,const double closePrice,
                         const double ema20,const double atr)
{
   if(!Use_MA_Break_Block || atr<=0.0)
      return false;

   double body=MathAbs(closePrice-openPrice);
   if(body<atr*MaxBodyThroughEMA_ATR)
      return false;

   bool crossed=((openPrice>ema20 && closePrice<ema20) ||
                 (openPrice<ema20 && closePrice>ema20));
   return crossed;
}

double SignalScore(const bool wantLong,
                   const double closePrice,
                   const double ema20,const double ema50,
                   const double ema100,const double ema200,
                   const double slopePips,const double adx,
                   const double rsi,const bool bos)
{
   double score=0.0;

   if(wantLong)
   {
      if(ema20>ema50) score+=20.0;
      if(ema50>ema100) score+=10.0;
      if(ema100>ema200) score+=10.0;
      if(closePrice>ema20) score+=10.0;
      if(slopePips>=MinFastMASlopePips) score+=10.0;
      if(rsi<RSIBuyMax) score+=5.0;
   }
   else
   {
      if(ema20<ema50) score+=20.0;
      if(ema50<ema100) score+=10.0;
      if(ema100<ema200) score+=10.0;
      if(closePrice<ema20) score+=10.0;
      if(slopePips<=-MinFastMASlopePips) score+=10.0;
      if(rsi>RSISellMin) score+=5.0;
   }

   if(bos) score+=25.0;
   if(adx>=ADXMin) score+=10.0;

   if(score>100.0) score=100.0;
   return score;
}

bool ApplyHTFPolicy(const bool wantLong,const int htfDir,double &score,bool &counterTrend)
{
   counterTrend=false;

   if(!Use_HTF_Trend_Filter)
   {
      if((wantLong && htfDir==-1) || (!wantLong && htfDir==1))
         counterTrend=true;
      return true;
   }

   if(htfDir==0)
   {
      if(HTF_Mismatch_Mode==2)
         return false;
      if(HTF_Mismatch_Mode==1)
         score-=10.0;
      return true;
   }

   bool aligned=(wantLong && htfDir==1) || (!wantLong && htfDir==-1);
   if(aligned)
      return true;

   counterTrend=true;

   if(Trade_Only_Trend_Direction)
      return false;

   if(HTF_Mismatch_Mode==2)
      return false;
   if(HTF_Mismatch_Mode==1)
      score-=15.0;

   return true;
}

void FireAlert(const bool isBuy,const bool counterTrend,
               const datetime barTime,const double price,const double score)
{
   if(barTime==g_lastAlertBar)
      return;

   string side=isBuy ? "BUY" : "SELL";
   string kind=counterTrend ? "COUNTER" : "TREND";
   string tf=EnumToString((ENUM_TIMEFRAMES)_Period);
   string msg=StringFormat("GoldSmartScalper v1.1.0 %s %s %s %s score=%.0f @ %.*f",
                           _Symbol,tf,side,kind,score,_Digits,price);

   if(EnablePopupAlert) Alert(msg);
   if(EnablePushNotification) SendNotification(msg);
   if(EnableSound) PlaySound(AlertSoundFile);

   g_lastAlertBar=barTime;
}

//+------------------------------------------------------------------+
//| Init                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0,BuyTrendBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,SellTrendBuffer,INDICATOR_DATA);
   SetIndexBuffer(2,BuyCounterBuffer,INDICATOR_DATA);
   SetIndexBuffer(3,SellCounterBuffer,INDICATOR_DATA);

   ArraySetAsSeries(BuyTrendBuffer,true);
   ArraySetAsSeries(SellTrendBuffer,true);
   ArraySetAsSeries(BuyCounterBuffer,true);
   ArraySetAsSeries(SellCounterBuffer,true);

   PlotIndexSetInteger(0,PLOT_ARROW,233);
   PlotIndexSetInteger(1,PLOT_ARROW,234);
   PlotIndexSetInteger(2,PLOT_ARROW,241);
   PlotIndexSetInteger(3,PLOT_ARROW,242);

   for(int p=0;p<4;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,"GoldSmartScalper v1.1.0");

   hEMA20=iMA(_Symbol,_Period,EMAFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA50=iMA(_Symbol,_Period,EMAMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA100=iMA(_Symbol,_Period,EMASlowPeriod,0,MODE_EMA,PRICE_CLOSE);
   hEMA200=iMA(_Symbol,_Period,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   hATR=iATR(_Symbol,_Period,ATRPeriod);
   hADX=iADX(_Symbol,_Period,ADXPeriod);
   hRSI=iRSI(_Symbol,_Period,RSIPeriod,PRICE_CLOSE);

   hH1EMA20=iMA(_Symbol,PERIOD_H1,EMAFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH1EMA50=iMA(_Symbol,PERIOD_H1,EMAMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH1EMA200=iMA(_Symbol,PERIOD_H1,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH4EMA20=iMA(_Symbol,PERIOD_H4,EMAFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH4EMA50=iMA(_Symbol,PERIOD_H4,EMAMidPeriod,0,MODE_EMA,PRICE_CLOSE);
   hH4EMA200=iMA(_Symbol,PERIOD_H4,EMATrendPeriod,0,MODE_EMA,PRICE_CLOSE);

   if(hEMA20==INVALID_HANDLE || hEMA50==INVALID_HANDLE ||
      hEMA100==INVALID_HANDLE || hEMA200==INVALID_HANDLE ||
      hATR==INVALID_HANDLE || hADX==INVALID_HANDLE || hRSI==INVALID_HANDLE ||
      hH1EMA20==INVALID_HANDLE || hH1EMA50==INVALID_HANDLE || hH1EMA200==INVALID_HANDLE ||
      hH4EMA20==INVALID_HANDLE || hH4EMA50==INVALID_HANDLE || hH4EMA200==INVALID_HANDLE)
   {
      Print("GoldSmartScalper v1.1.0: failed to create handles. Error=",GetLastError());
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
   if(hH1EMA20!=INVALID_HANDLE) IndicatorRelease(hH1EMA20);
   if(hH1EMA50!=INVALID_HANDLE) IndicatorRelease(hH1EMA50);
   if(hH1EMA200!=INVALID_HANDLE) IndicatorRelease(hH1EMA200);
   if(hH4EMA20!=INVALID_HANDLE) IndicatorRelease(hH4EMA20);
   if(hH4EMA50!=INVALID_HANDLE) IndicatorRelease(hH4EMA50);
   if(hH4EMA200!=INVALID_HANDLE) IndicatorRelease(hH4EMA200);
}

//+------------------------------------------------------------------+
//| Calculate                                                        |
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

   int need=EMATrendPeriod+MathMax(BOSLookback,ATRAverageBars)+AngleLookbackBars+20;
   if(rates_total<need)
      return 0;

   int maxShift=MathMin(MaxBarsToScan,rates_total-need);
   if(maxShift<1)
      return rates_total;

   for(int i=maxShift;i>=1;i--)
   {
      BuyTrendBuffer[i]=EMPTY_VALUE;
      SellTrendBuffer[i]=EMPTY_VALUE;
      BuyCounterBuffer[i]=EMPTY_VALUE;
      SellCounterBuffer[i]=EMPTY_VALUE;

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

      bool bosLong=BOSLong(i,high,close,rates_total);
      bool bosShort=BOSShort(i,low,close,rates_total);
      double slopePips=(ema20-ema20Past)/PipSize();

      bool longCandidate=(bosLong && close[i]>ema20 && slopePips>0.0 && rsi<RSIBuyMax);
      bool shortCandidate=(bosShort && close[i]<ema20 && slopePips<0.0 && rsi>RSISellMin);

      if(BreakthroughBlocked(open[i],close[i],ema20,atr))
      {
         longCandidate=false;
         shortCandidate=false;
      }

      int htfDir=CombinedHTFDirection(time[i]);

      if(longCandidate)
      {
         double score=SignalScore(true,close[i],ema20,ema50,ema100,ema200,slopePips,adx,rsi,bosLong);
         bool counter=false;
         if(ApplyHTFPolicy(true,htfDir,score,counter))
         {
            double minScore=counter ? Counter_Trend_Min_Score : Signal_Strength_Threshold;
            if(score>=minScore)
            {
               if(counter)
                  BuyCounterBuffer[i]=low[i]-atr*ArrowOffsetATR;
               else
                  BuyTrendBuffer[i]=low[i]-atr*ArrowOffsetATR;
            }
         }
      }

      if(shortCandidate)
      {
         double score=SignalScore(false,close[i],ema20,ema50,ema100,ema200,slopePips,adx,rsi,bosShort);
         bool counter=false;
         if(ApplyHTFPolicy(false,htfDir,score,counter))
         {
            double minScore=counter ? Counter_Trend_Min_Score : Signal_Strength_Threshold;
            if(score>=minScore)
            {
               if(counter)
                  SellCounterBuffer[i]=high[i]+atr*ArrowOffsetATR;
               else
                  SellTrendBuffer[i]=high[i]+atr*ArrowOffsetATR;
            }
         }
      }
   }

   BuyTrendBuffer[0]=EMPTY_VALUE;
   SellTrendBuffer[0]=EMPTY_VALUE;
   BuyCounterBuffer[0]=EMPTY_VALUE;
   SellCounterBuffer[0]=EMPTY_VALUE;

   if(BuyTrendBuffer[1]!=EMPTY_VALUE)
   {
      double s=0.0; CopyOne(hADX,0,1,s);
      FireAlert(true,false,time[1],close[1],s);
   }
   else if(SellTrendBuffer[1]!=EMPTY_VALUE)
   {
      double s=0.0; CopyOne(hADX,0,1,s);
      FireAlert(false,false,time[1],close[1],s);
   }
   else if(BuyCounterBuffer[1]!=EMPTY_VALUE)
   {
      double s=0.0; CopyOne(hADX,0,1,s);
      FireAlert(true,true,time[1],close[1],s);
   }
   else if(SellCounterBuffer[1]!=EMPTY_VALUE)
   {
      double s=0.0; CopyOne(hADX,0,1,s);
      FireAlert(false,true,time[1],close[1],s);
   }

   return rates_total;
}
