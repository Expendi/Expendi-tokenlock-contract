-- Query 1: Total Value Locked (TVL) - TimeLock
-- Calculates current TVL by token for the TimeLock contract
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding

with deposits as (
    select
        token,
        sum(amount) as total_deposited
    from expendi_base.TimeLock_evt_LockCreated
    where evt_block_time >= now() - interval '365' day
    group by 1
),

withdrawals as (
    select
        token,
        sum(amount) as total_withdrawn
    from expendi_base.TimeLock_evt_Withdrawn
    where evt_block_time >= now() - interval '365' day
    group by 1
)

select
    coalesce(d.token, w.token) as token,
    coalesce(d.total_deposited, 0) - coalesce(w.total_withdrawn, 0) as tvl_raw,
    -- For human-readable display, adjust decimals per token
    -- Using 18 decimals as default; join with tokens.erc20 for accurate decimals
    (coalesce(d.total_deposited, 0) - coalesce(w.total_withdrawn, 0)) / 1e18 as tvl_adjusted
from deposits d
full outer join withdrawals w
    on d.token = w.token
order by tvl_raw desc
