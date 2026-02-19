-- Query 2: Daily Lock Activity
-- Tracks daily lock creation activity for TimeLock contract
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding

select
    date_trunc('day', evt_block_time) as date,
    count(*) as locks_created,
    count(distinct depositor) as unique_depositors,
    sum(amount) as total_amount_locked_raw,
    sum(amount / 1e18) as total_amount_locked_adjusted
from expendi_base.TimeLock_evt_LockCreated
where evt_block_time >= now() - interval '30' day
group by 1
order by 1 desc
