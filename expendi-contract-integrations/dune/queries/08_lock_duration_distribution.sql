-- Query 8: Lock Duration Distribution
-- Analyzes the distribution of lock durations for TimeLock
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding
--
-- unlockTime is a Unix timestamp, evt_block_time is a timestamp
-- We calculate duration in days: (unlockTime - block_timestamp) / 86400

select
    case
        when (unlockTime - cast(extract(epoch from evt_block_time) as bigint)) / 86400 <= 7 then '0-7 days'
        when (unlockTime - cast(extract(epoch from evt_block_time) as bigint)) / 86400 <= 30 then '8-30 days'
        when (unlockTime - cast(extract(epoch from evt_block_time) as bigint)) / 86400 <= 90 then '31-90 days'
        when (unlockTime - cast(extract(epoch from evt_block_time) as bigint)) / 86400 <= 365 then '91-365 days'
        else '365+ days'
    end as lock_duration_bucket,
    count(*) as lock_count,
    sum(amount) as total_amount_raw,
    sum(amount / 1e18) as total_amount_adjusted,
    avg((unlockTime - cast(extract(epoch from evt_block_time) as bigint)) / 86400) as avg_duration_days
from expendi_base.TimeLock_evt_LockCreated
where evt_block_time >= now() - interval '365' day
group by 1
order by
    case lock_duration_bucket
        when '0-7 days' then 1
        when '8-30 days' then 2
        when '31-90 days' then 3
        when '91-365 days' then 4
        else 5
    end
