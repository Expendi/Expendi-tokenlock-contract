-- Query 3: YieldTimeLock - Yield Performance Tracking
-- Tracks withdrawal performance by joining deposits with withdrawals to calculate yield
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding
--
-- Event schemas:
--   YieldLockCreated: lockId, depositor, vault, underlyingToken, principalAssets, shares, unlockTime, label
--   YieldLockWithdrawn: lockId, depositor, vault, shares, totalAssets, fee, netAssets

with withdrawals as (
    select
        w.evt_block_time,
        w.lockId,
        w.vault,
        w.totalAssets,
        w.fee,
        w.netAssets,
        -- Join with deposit to get principal
        d.principalAssets
    from expendi_base.YieldTimeLock_evt_YieldLockWithdrawn w
    inner join expendi_base.YieldTimeLock_evt_YieldLockCreated d
        on w.lockId = d.lockId
    where w.evt_block_time >= now() - interval '90' day
)

select
    date_trunc('day', evt_block_time) as date,
    vault,
    count(*) as withdrawals,
    sum(totalAssets) as total_assets_withdrawn,
    sum(principalAssets) as total_principal,
    sum(totalAssets - principalAssets) as total_yield_earned,
    sum(fee) as total_fees_paid,
    sum(netAssets) as total_net_to_users,
    avg(
        case
            when principalAssets > 0
            then (totalAssets - principalAssets) * 100.0 / principalAssets
            else 0
        end
    ) as avg_yield_pct
from withdrawals
group by 1, 2
order by 1 desc
