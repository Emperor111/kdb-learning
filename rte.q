/ =========================================================
/ KDB+ RTE PoC: VWAP + ALL Transformations
/ =========================================================

/ *** 1. Configuration ***
TP_HOST: `::      / Localhost
TP_PORT: 5010     / Port for the Tickerplant

/ *** 2. Data Storage (In-Memory) ***

/ Log table for raw data (requires 'date' to satisfy the new functions)
trade_log: ([] date:`date$(); time:`time$(); sym:`symbol$(); price:`float$(); size:`long$())

/ Running aggregation state for VWAP
vwap_agg: ([] sym:`$(); sum_pv:0n; sum_v:0n)

/ =========================================================
/ *** 3. Transformation Functions (All Screenshots) ***
/ =========================================================

/ Function: getFilledTab (NEWLY ADDED)
/ Purpose: Fills null values forward for specified columns, filtered by a single date (dt) and symbol (s).
getFilledTab:{[tab;s;dt;col]
    col:(),col;
    
    / Create the fills clause (applies 'fills' to each column)
    colClause:col!fills,'col;
    
    / 1. Select data matching a SINGLE date (dt) and sym
    tab:?[tab;
        ((=;`date;dt); $[`~s;1b;(in;`sym;(),s)]);
        0b;
        {x!x} `date`time`sym union (),col
    ];

    / 2. Update with forward fill by symbol
    ![tab;();(enlist `sym)!enlist `sym;colClause]
 };

/ Function: FilledTab (Previously provided)
/ Purpose: Similar to getFilledTab but accepts multiple datetimes for date filtering.
FilledTab:{[tab;s;datetimes;col]
    col:(),col;
    datetimes:(),datetimes;
    colClause:col!fills,'col;
    
    / 1. Select data matching MULTIPLE dates (in;`date;datetimes) and sym
    tab:?[tab;
        ((in;`date;datetimes); $[`~s;1b;(in;`sym;(),s)]);
        0b;
        {x!x} `date`time`sym union (),col
    ];

    / 2. Update with forward fill by symbol
    ![tab;();(enlist `sym)!enlist `sym;colClause]
 };

/ Function: strikeAsOf (Previously provided)
/ Purpose: Returns data as of specific datetimes using bucket join (bin).
strikeAsOf:{[tab;s;datetimes;col]
    datelist:distinct `date$datetimes;
    col:$[`~col;cols tab;col];
    col:`time union col;
    symClause:$[`~s;1b;(in;`sym;(),s)];
    
    / Use FilledTab to retrieve and fill the base data
    tab:FilledTab[tab;s;datelist;col];

    / Create date_time column for the binary search
    tab:update date_time:date+time from tab;
    col:`date_time union col except `time;
    T:`s# asc datetimes;
    
    / Perform the As-Of Logic using bin
    res:?[tab;
        (symClause;((;not;>);`date_time;(max;T)));
        `sym`timebucket!(`sym;(T;(+;1;(bin;T;`date_time))));
        col!((last;x)) each col
    ];
    
    res
 };

/ =========================================================
/ *** 4. Real-Time Engine Logic (RTE) ***
/ =========================================================

/ Connection Initialization
.rte.init:{
    0N!`"Connecting to Tickerplant at ", string[TP_PORT], "...";
    h: hopen (TP_HOST; TP_PORT);
    neg[h] (`.u.sub; `trade; ``; `.rte.reset);
    .u.upd: .rte.upd;
    0N!`"RTE Ready. Listening for updates...";
    h
 };

/ The Reset Function
.rte.reset:{[tab; x]
    trade_log:: delete from trade_log;
    vwap_agg:: ([] sym:`$(); sum_pv:0n; sum_v:0n);
 };

/ The Update Function (Called on every tick)
.rte.upd:{[tab; x]
    if[not tab=`trade; :()];

    / --- A. Data Persistence for Transformations ---
    / We inject today's date (.z.d) as the transformation functions require a 'date' column
    x_with_date: update date:.z.d from x;
    `trade_log insert x_with_date;

    / --- B. Real-Time VWAP Analytics ---
    x: update pv:price * size from x;
    new_agg: select sum_pv:sum pv, sum_v:sum size by sym from x;
    vwap_agg:: .[vwap_agg; (); upsert; new_agg];
    result: update vwap: sum_pv % sum_v from vwap_agg;
    
    0N!(`VWAP_LATEST; .z.p; result);
 };

/ *** 5. Startup ***
.rte.init[];
\