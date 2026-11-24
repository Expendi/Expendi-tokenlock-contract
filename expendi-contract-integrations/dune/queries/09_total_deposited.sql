-- Query 9: Total Deposited (all time) - YieldTimeLock
-- Principal of every lock ever created, with and without the largest depositor.
-- Money that is re-locked counts again, so this is volume through the contract,
-- not savings held. Counter visualization.

with locks as (
    select
        depositor,
        cast(principalAssets as double) as principal
    from expendi_timelock_base.yieldtimelock_evt_yieldlockcreated
),

top_depositor as (
    select
        depositor,
        sum(principal) as deposited
    from locks
    group by 1
    order by 2 desc
    limit 1
)

select
    count(*) as locks_created,
    count(distinct l.depositor) as unique_depositors,
    round(sum(l.principal) / 1e6, 2) as total_deposited,
    round((sum(l.principal) - max(t.deposited)) / 1e6, 2) as total_deposited_excluding_top_depositor,
    round(max(t.deposited) * 100 / sum(l.principal), 2) as top_depositor_share_pct
from locks l
cross join top_depositor t
