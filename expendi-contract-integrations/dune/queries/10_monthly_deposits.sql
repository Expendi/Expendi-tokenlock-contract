-- Query 10: Monthly Deposits - YieldTimeLock
-- Principal put into new locks per month, split into the largest depositor
-- (by all-time principal) and everyone else. Stacked bar chart.
-- Months with no locks do not appear.

with locks as (
    select
        evt_block_time,
        depositor,
        cast(principalAssets as double) as principal
    from expendi_timelock_base.yieldtimelock_evt_yieldlockcreated
),

top_depositor as (
    select depositor
    from locks
    group by 1
    order by sum(principal) desc
    limit 1
)

select
    date_trunc('month', l.evt_block_time) as month,
    count(*) as locks_created,
    count(distinct l.depositor) as unique_depositors,
    round(sum(l.principal) / 1e6, 2) as deposited,
    round(sum(case when l.depositor = t.depositor then l.principal else 0 end) / 1e6, 2) as from_top_depositor,
    round(sum(case when l.depositor = t.depositor then 0 else l.principal end) / 1e6, 2) as from_everyone_else
from locks l
cross join top_depositor t
group by 1
order by 1
