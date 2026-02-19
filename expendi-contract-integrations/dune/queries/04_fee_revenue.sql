-- Query 4: Fee Revenue Analysis
-- Tracks fee collection across YieldTimeLock contract
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding
--
-- Event schema:
--   FeeCollected(uint256 indexed lockId, address indexed token, uint256 amount)

select
    date_trunc('week', evt_block_time) as week,
    token,
    sum(amount) as total_fees_collected_raw,
    sum(amount / 1e18) as total_fees_collected_adjusted,
    count(*) as fee_events
from expendi_base.YieldTimeLock_evt_FeeCollected
where evt_block_time >= now() - interval '180' day
group by 1, 2
order by 1 desc
