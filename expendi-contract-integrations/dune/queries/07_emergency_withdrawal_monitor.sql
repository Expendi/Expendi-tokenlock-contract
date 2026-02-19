-- Query 7: Emergency Withdrawal Monitor
-- Monitors emergency withdrawals initiated by owner
-- Note: Replace 'expendi_base' with your actual namespace after Dune decoding
--
-- Event schema:
--   EmergencyWithdrawal(uint256 indexed lockId, address indexed vault, uint256 shares, uint256 assets)

select
    evt_block_time,
    lockId,
    vault,
    shares,
    assets,
    assets / 1e18 as assets_adjusted,
    evt_tx_hash
from expendi_base.YieldTimeLock_evt_EmergencyWithdrawal
order by evt_block_time desc
limit 100
