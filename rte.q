/ tick/rte.q
/ Usage: q tick/rte.q -p 5014

\d .rte

/ --- Configuration ---
TP_PORT:5010;

/ --- Schema Definitions ---
trade_log:([]date:`date$();time:`timespan$();sym:`symbol$();price:`float$();size:`long$();side:`symbol$());
vwap_agg:([sym:`symbol$()] sum_pv:`float$(); sum_v:`long$(); vwap:`float$());

/ =========================================================
/ *** 3. Transformation Functions ***
/ =========================================================

/ Function: getFilledTab
getFilledTab:{[tab;s;dt;col]
    col:(),col;
    colClause:col!fills,'col;
    tab:?[tab;
        ((=;`date;dt); $[`~s;1b;(in;`sym;(),s)]);
        0b;
        {x!x} `date`time`sym union (),col
    ];
    ![tab;();(enlist `sym)!enlist `sym;colClause]
 };

/ Function: FilledTab
FilledTab:{[tab;s;datetimes;col]
    col:(),col;
    datetimes:(),datetimes;
    colClause:col!fills,'col;
    tab:?[tab;
        ((in;`date;datetimes); $[`~s;1b;(in;`sym;(),s)]);
        0b;
        {x!x} `date`time`sym union (),col
    ];
    ![tab;();(enlist `sym)!enlist `sym;colClause]
 };

/ Function: strikeAsOf
/ Purpose: Returns data as of specific datetimes using bucket join (bin)
strikeAsOf:{[tab;s;datetimes;col]
    datelist:distinct `date$datetimes;
    col:$[`~col;cols tab;col];
    col:`time union col;
    symClause:$[`~s;1b;(in;`sym;(),s)];
    
    / 1. Fill base data
    tab:.rte.FilledTab[tab;s;datelist;col];

    / 2. Prepare columns for AsOf Join
    tab:update date_time:date+time from tab;
    col:`date_time union col except `time;
    T:`s# asc datetimes;
    
    / 3. Perform As-Of Logic (Functional Select)
    / Syntax Fix: Nested (not; (>...)) correctly
    res:?[tab;
       (symClause; (not; (>; `date_time; (max; T))) );
       `sym`timebucket!(`sym; (T; (bin; T; `date_time)) );
       col!{(last;x)} each col
    ];
    
    res
 };

/ =========================================================
/ *** End Transformations ***
/ =========================================================

/ --- Update Logic ---
upd:{[t;x]
    if[not t=`trade;:()];
    
    / Normalize Data
    data:$[98h=type x; x; 0h=type x; [colsVal:$[4<count x; -4#x; x]; flip `time`sym`price`side!colsVal]; flip `time`sym`price`side!x];

    / Augment & Insert
    data:update date:.z.d, size:100j from data;
    `trade_log insert select date, time, sym, price, size, side from data;

    / VWAP Calc
    batch:select sum_pv:sum price*size, sum_v:sum size by sym from data;
    .rte.vwap_agg+:batch;
    update vwap:sum_pv%sum_v from `.rte.vwap_agg;

    / Clean Print
    /-1 "VWAP UPDATE @ ",string[.z.p]," : ", .Q.s1 select sym, vwap from .rte.vwap_agg;
    -1 "VWAP UPDATE @ ",string[.z.p];
    show select sym, vwap from .rte.vwap_agg;
    -1 "";
 };

/ --- Initialization ---
init:{
    -1 ">>> Initializing RTE...";
    h:@[hopen;TP_PORT;{-1 "!!! ERROR: Connection failed: ",x; 0i}];
    if[h=0i; -1 ">>> Running in offline mode."; :()];
    neg[h]"(.u.sub[`trade;`])";
    -1 ">>> RTE Ready and Subscribed.";
    h
 };

/ --- GLOBAL MAPPINGS ---
\d .
upd:.rte.upd;
.u.upd:.rte.upd;
.q.upd:.rte.upd;

/ --- EXECUTE ---
.rte.init[];
